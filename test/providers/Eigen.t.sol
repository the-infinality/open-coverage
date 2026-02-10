// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20v5} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {EigenTestDeployer} from "../utils/EigenTestDeployer.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {CoveragePosition, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {
    IAllocationManager,
    IAllocationManagerTypes,
    IAllocationManagerEvents
} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {ICoverageAgent} from "src/interfaces/ICoverageAgent.sol";
import {IExampleCoverageAgent} from "src/interfaces/IExampleCoverageAgent.sol";
import {ExampleCoverageAgent} from "src/ExampleCoverageAgent.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {IDiamondOwner} from "src/diamond/interfaces/IDiamondOwner.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";
import {CoverageClaim, CoverageClaimStatus} from "src/interfaces/ICoverageProvider.sol";
import {UniswapV3SwapperEngine} from "src/swapper-engines/UniswapV3SwapperEngine.sol";
import {UniswapAddressbook} from "utils/UniswapHelper.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {PriceStrategy, AssetPair} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {ISlashCoordinator, SlashCoordinationStatus} from "src/interfaces/ISlashCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

contract EigenTest is EigenTestDeployer {
    IEigenOperatorProxy public operator;
    MockPriceOracle public mockPriceOracle;
    address public staker;

    // Cast the diamond to the interfaces for easier access
    IEigenServiceManager eigenServiceManager;
    ICoverageProvider eigenCoverageProvider;
    IAssetPriceOracleAndSwapper eigenPriceOracle;
    ISwapperEngine public uniswapV3SwapperEngine;

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);
    }

    function _stakeAndDelegateToOperator(uint256 stakeAmount) internal {
        vm.startPrank(staker);
        IStrategyManager strategyManager = _getStrategyManager();

        // Approve strategy to spend tokens
        _getTestStrategy().underlyingToken().approve(address(strategyManager), stakeAmount);

        // Deposit into strategy
        strategyManager.depositIntoStrategy(_getTestStrategy(), _getTestStrategy().underlyingToken(), stakeAmount);

        // Delegate to operator (empty signature since no delegationApprover)
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySignature =
            ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0});
        _getDelegationManager().delegateTo(address(operator), emptySignature, bytes32(0));

        deal(coverageAgent.asset(), address(coverageAgent), 100e6);

        vm.stopPrank();
    }

    function setUp() public override {
        super.setUp();

        staker = makeAddr("staker");

        deal(rETH, staker, 1000e18);

        // Cast diamond to interfaces
        eigenServiceManager = IEigenServiceManager(address(eigenCoverageDiamond));
        eigenCoverageProvider = ICoverageProvider(address(eigenCoverageDiamond));
        eigenPriceOracle = IAssetPriceOracleAndSwapper(address(eigenCoverageDiamond));

        operator = IEigenOperatorProxy(
            address(new EigenOperatorProxy(eigenServiceManager.eigenAddresses(), address(this), ""))
        );

        IPermissionController(eigenServiceManager.eigenAddresses().permissionController).acceptAdmin(address(operator));

        coverageAgent.registerCoverageProvider(address(eigenCoverageDiamond));
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);

        mockPriceOracle = new MockPriceOracle(100000e18, rETH, USDC);

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();
        uniswapV3SwapperEngine = new UniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.viewQuoterV3
        );

        // V3 multi-hop path: rETH -> WETH (fee: 100) -> USDC (fee: 500)
        // For EXACT_OUT, path is reversed: output -> fee -> intermediate -> fee -> input
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee rETH-WETH
            WETH,
            uint24(500), // 0.05% fee WETH-USDC
            USDC
        );

        eigenPriceOracle.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_RevertWhen_register_not_owner() public {
        address nonOwner = makeAddr("nonOwner");
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, address(this)));
        eigenPriceOracle.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_registerCoverageAgent() public {
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 10000);
    }

    /// @notice Test that coverage agent emits MetadataUpdated on deployment
    function test_coverageAgent_emitsMetadataUpdated_onDeployment() public {
        string memory uri = "https://coverage.example.com/agent-metadata.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(uri);
        new ExampleCoverageAgent(address(this), USDC, uri);
    }

    /// @notice Test that coverage agent emits MetadataUpdated when updateMetadata is called
    function test_coverageAgent_emitsMetadataUpdated_onUpdate() public {
        string memory newUri = "https://new-metadata.example.com/updated.json";
        vm.expectEmit(false, false, false, true);
        emit ICoverageAgent.MetadataUpdated(newUri);
        coverageAgent.updateMetadata(newUri);
    }

    function test_allocate() public {
        _setupwithAllocations();
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageDiamond), id: eigenServiceManager.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenServiceManager.eigenAddresses().allocationManager
            ).getAllocation(address(operator), operatorSet, _getTestStrategy());
        assertEq(allocation.currentMagnitude, 1e18);
    }

    function test_createPosition() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        // Expect PositionCreated event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionCreated(0);

        uint256 positionId = eigenCoverageProvider.createPosition(data, "");
        assertEq(positionId, 0);
    }

    function test_closePosition() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Expect PositionClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionClosed(positionId);

        eigenCoverageProvider.closePosition(positionId);
        assertEq(eigenCoverageProvider.position(positionId).expiryTimestamp, block.timestamp);
    }

    function test_RevertWhen_closePosition_expired() public {
        _setupwithAllocations();

        uint256 expiryTimestamp = block.timestamp + 365 days;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: expiryTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Warp past the expiry timestamp
        vm.warp(block.timestamp + 366 days);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.PositionExpired.selector, positionId, expiryTimestamp));
        eigenCoverageProvider.closePosition(positionId);
    }

    function test_RevertWhen_closePosition_notAuthorized() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Try to close from an unauthorized address
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IEigenServiceManager.NotOperatorAuthorized.selector, address(operator), unauthorized)
        );
        eigenCoverageProvider.closePosition(positionId);
    }

    /// @notice Test that anyone can close a position when the strategy is no longer whitelisted
    function test_closePosition_strategyNotWhitelisted() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Now anyone can close the position (no authorization required)
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);

        // Expect PositionClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.PositionClosed(positionId);

        eigenCoverageProvider.closePosition(positionId);
    }

    function test_claimPosition() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(10e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Expect ClaimIssued event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimIssued(positionId, 0, 1000e6, 30 days);

        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, 10e6);
        assertEq(claim.positionId, positionId);

        // Verify claim backing is positive (fully backed)
        int256 backing = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backing, 0, "Claim should be fully backed after issuance");
    }

    /// @notice Fuzz test to verify claim coverage with various claim amounts up to the maximum staked coverage
    /// @param claimAmountBps The claim amount as a percentage of maximum coverage in basis points (1-10000)
    ///                       This will be bounded to ensure we don't exceed available coverage
    function testFuzz_claimPosition(uint256 claimAmountBps) public {
        _setupwithAllocations();

        uint256 stakeAmount = 10e18;
        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Calculate the maximum coverage available based on allocated stake
        uint256 maxCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Bound claimAmountBps to 1-10000 (0.01% to 100% of max coverage)
        // Ensure we have at least 1 unit of claim amount
        claimAmountBps = bound(claimAmountBps, 1, 10000);
        uint256 claimAmount = (maxCoverage * claimAmountBps) / 10000;

        // Ensure claimAmount is at least 1 to pass validation
        if (claimAmount == 0) {
            claimAmount = 1;
        }

        // Calculate reward proportionally (using a reasonable reward rate)
        // Using 1% of claim amount as reward, minimum 1e6
        uint256 reward = claimAmount / 100;
        if (reward < 1e6) {
            reward = 1e6;
        }

        // Give the coverage agent a large balance to handle rewards for any claim amount
        // Reward is at most maxCoverage/100 (when claimAmount = maxCoverage), but ensure we have enough
        // Set balance to maxCoverage to provide ample buffer for any reward calculation
        deal(coverageAgent.asset(), address(coverageAgent), maxCoverage);

        vm.startPrank(address(coverageAgent));
        // Approve enough tokens for the reward
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);

        // Track the expected claim ID (should be 0 for first claim in a fresh test)
        // Since each fuzz test run is independent, this will be the first claim
        uint256 expectedClaimId = 0;
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, reward);
        vm.stopPrank();

        // Verify claim ID (should be 0 for first claim)
        assertEq(claimId, expectedClaimId);

        // Verify claim properties
        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, claimAmount);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, reward);
        assertEq(claim.positionId, positionId);

        // Verify claim backing is non-negative (fully backed or at least not in deficit)
        int256 backing = eigenCoverageProvider.claimBacking(claimId);
        assertGe(backing, 0, "Claim should be fully backed after issuance");
    }

    function test_getAllocationedStrategies() public {
        // Setup with allocations
        _setupwithAllocations();

        address[] memory strategies =
            eigenServiceManager.getAllocationedStrategies(address(operator), address(coverageAgent));
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
    }

    function test_whitelistedStrategies() public view {
        // Initially should have 1 strategy (set in setUp)
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));
    }

    function test_providerTypeId() public view {
        // Should return the correct provider type ID (20 for Eigen coverage provider)
        uint256 typeId = eigenCoverageProvider.providerTypeId();
        assertEq(typeId, 20);
    }

    function test_whitelistedStrategies_afterRemoval() public {
        // Remove the strategy from whitelist
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);

        // Should be empty now
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 0);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));
    }

    function test_whitelistedStrategies_addAndRemove() public {
        // Start with 1 strategy from setUp
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);

        // Remove the strategy
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
        strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 0);

        // Re-add the strategy
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);
        strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
    }

    function test_RevertWhen_whitelistStrategy_alreadyWhitelisted() public {
        // Strategy is already whitelisted in setUp
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        // Trying to whitelist the same strategy again should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.StrategyAssetAlreadyRegistered.selector,
                address(_getTestStrategy().underlyingToken())
            )
        );
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), true);
    }

    function test_RevertWhen_whitelistStrategy_sameAssetDifferentStrategy() public {
        // Strategy is already whitelisted in setUp
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        // Create a mock strategy with the same underlying token
        MockStrategy mockStrategy = new MockStrategy(address(_getTestStrategy().underlyingToken()));

        // Trying to whitelist a different strategy with the same asset should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.StrategyAssetAlreadyRegistered.selector,
                address(_getTestStrategy().underlyingToken())
            )
        );
        eigenServiceManager.setStrategyWhitelist(address(mockStrategy), true);
    }

    function test_whitelistStrategy_sameAssetAfterRemoval() public {
        // Strategy is already whitelisted in setUp
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        // Create a mock strategy with the same underlying token
        MockStrategy mockStrategy = new MockStrategy(address(_getTestStrategy().underlyingToken()));

        // First remove the existing strategy
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(address(_getTestStrategy())));

        // Now we can whitelist the new strategy with the same asset
        eigenServiceManager.setStrategyWhitelist(address(mockStrategy), true);
        assertTrue(eigenServiceManager.isStrategyWhitelisted(address(mockStrategy)));

        // Verify the asset is now mapped to the new strategy
        address[] memory strategies = eigenServiceManager.whitelistedStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(mockStrategy));
    }

    function test_RevertWhen_claimPosition_insufficientCoverageOnClaim() public {
        _setupwithAllocations();

        // Calculate the minimum stake needed to cover 1000e6 USDC
        // The coverage calculation converts allocated stake (in strategy asset) to coverage asset (USDC)
        // We need to find what stake amount would result in coverage < 1000e6 USDC
        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        uint256 claimAmount = 1000e6; // USDC

        // The coverage calculation does: getQuote(allocatedStake, coverageAsset, strategyAsset)
        // This converts allocatedStake FROM coverageAsset TO strategyAsset
        // To find the stake that gives us exactly claimAmount coverage, we reverse it:
        // getQuote(claimAmount, strategyAsset, coverageAsset) gives us the stake amount
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(claimAmount, strategyAsset, coverageAsset);

        // Stake slightly less than required to trigger insufficient coverage error
        // Use 99% of required stake to ensure we're under the threshold
        uint256 stakeAmount = (requiredStake * 90) / 100;

        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 coverageAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientCoverageAvailable.selector, claimAmount - coverageAllocated
            )
        );
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
    }

    /// @notice Fuzz test to verify insufficient coverage error with various stake amounts
    /// @param stakePercentBps The stake amount as a percentage of required stake in basis points (0-10000)
    ///                         Values < 10000 (100%) will trigger insufficient coverage
    function testFuzz_RevertWhen_claimPosition_insufficientCoverageOnClaim(uint256 stakePercentBps) public {
        _setupwithAllocations();

        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        uint256 claimAmount = 1000e6; // USDC

        // Calculate the minimum stake needed to cover the claim amount
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(claimAmount, strategyAsset, coverageAsset);

        // Bound stakePercentBps to a reasonable range: 0-99% of required stake
        // This ensures we always have insufficient coverage
        // Using basis points: 0 = 0%, 9900 = 99%
        stakePercentBps = bound(stakePercentBps, 0, 9900);
        uint256 stakeAmount = (requiredStake * stakePercentBps) / 10000;

        // Skip if stakeAmount is 0 (would cause issues with staking)
        if (stakeAmount < 1e3) {
            stakeAmount = 1e3;
        }

        _stakeAndDelegateToOperator(stakeAmount);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 coverageAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.InsufficientCoverageAvailable.selector, claimAmount - coverageAllocated
            )
        );
        eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
    }

    function test_RevertWhen_claimPosition_invalidAmount() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(10e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        vm.expectRevert(ICoverageProvider.ZeroAmount.selector);
        eigenCoverageProvider.issueClaim(positionId, 0, 30 days, 10e6);
        vm.stopPrank();
    }

    function test_RevertWhen_claimPosition_notCoverageAgent() public {
        _setupwithAllocations();

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        uint256 positionId = eigenCoverageProvider.createPosition(data, "");
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, staker, address(coverageAgent))
        );
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
    }

    function test_positionMaxAmount() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1e16);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");
        assertApproxEqAbs(eigenCoverageProvider.positionMaxAmount(positionId), 35735542, 4e5);
    }

    function test_RevertWhen_claimPosition_durationExceedsMax() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.DurationExceedsMax.selector, 30 days, 365 days));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 365 days, 10e6);
        vm.stopPrank();
    }

    function test_RevertWhen_claimPosition_insufficientReward() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        uint256 amount = 1000e6;
        uint256 duration = 30 days;
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InsufficientReward.selector, minimumReward, 10));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10);
        vm.stopPrank();
    }

    function test_RevertWhen_claimPosition_durationExceedsExpiry() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        // Create position with expiry 100 days from now
        uint256 expiryTimestamp = block.timestamp + 100 days;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 0, // No max duration limit
            expiryTimestamp: expiryTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Try to claim with duration that would exceed expiry (101 days)
        uint256 duration = 101 days;
        uint256 completionTimestamp = block.timestamp + duration;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.DurationExceedsExpiry.selector, expiryTimestamp, completionTimestamp
            )
        );
        eigenCoverageProvider.issueClaim(positionId, 1000e6, duration, 10e6);
        vm.stopPrank();
    }

    function test_captureRewards_refundableNone() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 amount;
        uint32 duration;
        uint32 distributionStartTime;

        // Same-block capture returns 0 (elapsedDuration == 0)
        (amount, duration,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        // Refundable.None: full reward is capturable immediately after any time elapses
        vm.warp(block.timestamp + 1);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6, "Full reward should be capturable immediately for None policy");

        // Second capture returns 0 (already fully distributed)
        vm.warp(block.timestamp + 40 days);
        (amount,,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0, "No remaining reward to capture");
    }

    function test_captureRewards_refundableTimeWeighted() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1000e18);

        // Create the position
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 amount;
        uint32 duration;
        uint32 distributionStartTime;

        (amount, duration,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 15 days);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 5e6);
        assertEq(duration, 15 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 15 days));

        vm.warp(block.timestamp + 25 days);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 5e6);
        assertEq(duration, 15 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 25 days));
    }

    // ============ Slashing Test Helper Functions ============

    /// @notice Sets up a slashing test: allocations, staking, and position creation
    /// @param stakeAmount Amount to stake and delegate to operator
    /// @param slashCoordinator Address of slash coordinator (address(0) for direct slashing)
    /// @param refundable Refundable type for the position
    /// @return positionId The created position ID
    function _setupSlashingPosition(uint256 stakeAmount, address slashCoordinator, Refundable refundable)
        internal
        returns (uint256 positionId)
    {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(stakeAmount);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: refundable,
            slashCoordinator: slashCoordinator,
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        positionId = eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Sets up a slashing test with default parameters (no coordinator, Refundable.None)
    /// @param stakeAmount Amount to stake and delegate to operator
    /// @return positionId The created position ID
    function _setupSlashingPosition(uint256 stakeAmount) internal returns (uint256 positionId) {
        return _setupSlashingPosition(stakeAmount, address(0), Refundable.None);
    }

    /// @notice Creates a claim and approves tokens for reward payment
    /// @param positionId The position ID to create claim for
    /// @param claimAmount Amount of coverage to claim
    /// @param duration Duration of the coverage claim
    /// @param reward Reward amount for the coverage provider
    /// @param timeOffset Optional time offset to warp after claim creation (0 = no warp)
    /// @return claimId The created claim ID
    function _createAndApproveClaim(
        uint256 positionId,
        uint256 claimAmount,
        uint256 duration,
        uint256 reward,
        uint256 timeOffset
    ) internal returns (uint256 claimId) {
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, duration, reward);

        if (timeOffset > 0) {
            vm.warp(block.timestamp + timeOffset);
        }
        vm.stopPrank();

        return claimId;
    }

    /// @notice Creates a claim with default duration (30 days) and no time warp
    /// @param positionId The position ID to create claim for
    /// @param claimAmount Amount of coverage to claim
    /// @param reward Reward amount for the coverage provider
    /// @return claimId The created claim ID
    function _createAndApproveClaim(uint256 positionId, uint256 claimAmount, uint256 reward)
        internal
        returns (uint256 claimId)
    {
        return _createAndApproveClaim(positionId, claimAmount, 30 days, reward, 0);
    }

    /// @notice Executes slashing for given claim IDs and amounts
    /// @param claimIds Array of claim IDs to slash
    /// @param amounts Array of amounts to slash (must match claimIds length)
    /// @param timeOffset Optional time offset to warp before slashing (0 = no warp)
    /// @return statuses Array of slash statuses returned from slashClaims
    function _executeSlash(uint256[] memory claimIds, uint256[] memory amounts, uint256 timeOffset)
        internal
        returns (CoverageClaimStatus[] memory statuses)
    {
        if (timeOffset > 0) {
            vm.warp(block.timestamp + timeOffset);
        }

        vm.startPrank(address(coverageAgent));
        statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        return statuses;
    }

    /// @notice Executes slashing with no time warp
    /// @param claimIds Array of claim IDs to slash
    /// @param amounts Array of amounts to slash (must match claimIds length)
    /// @return statuses Array of slash statuses returned from slashClaims
    function _executeSlash(uint256[] memory claimIds, uint256[] memory amounts)
        internal
        returns (CoverageClaimStatus[] memory statuses)
    {
        return _executeSlash(claimIds, amounts, 0);
    }

    /// @notice Helper to create claimIds and amounts arrays for a single claim
    /// @param claimId The claim ID to slash
    /// @param amount The amount to slash
    /// @return claimIds Array with single claim ID
    /// @return amounts Array with single amount
    function _prepareSingleSlash(uint256 claimId, uint256 amount)
        internal
        pure
        returns (uint256[] memory claimIds, uint256[] memory amounts)
    {
        claimIds = new uint256[](1);
        amounts = new uint256[](1);
        claimIds[0] = claimId;
        amounts[0] = amount;
    }

    function test_slashClaims() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify claim backing before slashing
        int256 backingBeforeSlash = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeSlash, 0, "Claim should be fully backed before slashing");

        // Get asset addresses
        address coverageAsset = coverageAgent.asset();
        address positionAsset = eigenCoverageProvider.position(positionId).asset;

        // Check balances before slashing
        uint256 contractCoverageBalanceBefore = IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentBalanceBefore = IERC20(coverageAsset).balanceOf(address(coverageAgent));
        uint256 coverageAgentCoordinatorBalanceBefore =
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        uint256 contractPositionBalanceBefore = IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond));

        uint256 slashAmount = 10e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);

        // Verify coverage agent has the same balance as before the slashing
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)),
            coverageAgentBalanceBefore,
            "Coverage agent should have exact same amount before and after slashing"
        );

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()))
                - coverageAgentCoordinatorBalanceBefore,
            slashAmount,
            "Coverage agent coordinator should receive exact slashed amount"
        );

        // Verify contract coverage asset balance returns to baseline (tokens transferred out)
        assertEq(
            IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond)),
            contractCoverageBalanceBefore,
            "Contract should transfer out all slashed coverage tokens"
        );

        // Verify position asset balance returns to baseline (no tokens left over)
        assertEq(
            IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond)),
            contractPositionBalanceBefore,
            "No position asset should remain after conversion to coverage asset"
        );
    }

    // ============ Comprehensive Slashing Flow Tests ============

    /// @notice Test slashing a claim with partial amount
    function test_slashClaims_partialAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify claim backing before slashing
        int256 backingBeforeSlash = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeSlash, 0, "Claim should be fully backed before slashing");

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 500e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 500e6);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing multiple claims at once
    function test_slashClaims_multipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        vm.stopPrank();

        // Verify both claims are fully backed after issuance
        int256 backing1 = eigenCoverageProvider.claimBacking(claimId1);
        int256 backing2 = eigenCoverageProvider.claimBacking(claimId2);
        assertGt(backing1, 0, "First claim should be fully backed");
        assertGt(backing2, 0, "Second claim should be fully backed");

        uint256[] memory claimIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        claimIds[0] = claimId1;
        claimIds[1] = claimId2;
        amounts[0] = 1000e6;
        amounts[1] = 500e6;

        // Expect ClaimSlashed events for both claims
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId1, 1000e6);
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId2, 500e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(statuses[1]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId1).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId2).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing with exact claim amount
    function test_slashClaims_exactAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);
    }

    /// @notice Test that slashing transfers tokens to coverage agent
    function test_slashClaims_tokenTransfer() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 initialBalance =
            IERC20(coverageAgent.asset()).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        _executeSlash(claimIds, amounts);

        uint256 finalBalance =
            IERC20(coverageAgent.asset()).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));
        // The coverage agent should receive the slashed amount (1000e6 USDC)
        // Account for potential swap slippage - allow 1% tolerance
        uint256 expectedMinBalance = initialBalance + (1000e6 * 99) / 100;
        assertGe(finalBalance, expectedMinBalance);
    }

    /// @notice Test slashing immediately after claim creation should succeed
    /// @dev The code allows slashing at any time during the coverage period (createdAt <= block.timestamp <= createdAt + duration)
    function test_slashClaims_immediatelyAfterCreation() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify claim backing immediately after creation
        int256 backingBeforeSlash = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeSlash, 0, "Claim should be fully backed immediately after creation");

        // Slash immediately after creation (should succeed)
        uint256[] memory claimIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        claimIds[0] = claimId;
        amounts[0] = 1000e6;

        // Expect ClaimSlashed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test slashing after duration elapsed should revert
    function test_RevertWhen_slashClaims_afterDuration() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoverageProvider.ClaimExpired.selector,
                claimId,
                eigenCoverageProvider.claim(claimId).createdAt + 30 days
            )
        );
        _executeSlash(claimIds, amounts, 31 days);
    }

    /// @notice Test slashing with amount exceeding claim should revert
    function test_RevertWhen_slashClaims_amountExceedsClaim() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 0);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1001e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.SlashAmountExceedsClaim.selector, claimId, 1001e6, 1000e6)
        );
        _executeSlash(claimIds, amounts, 15 days);
    }

    /// @notice Test slashing with invalid claim status should revert
    function test_RevertWhen_slashClaims_invalidStatus() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 31 days);

        // Expect ClaimClosed event
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        // Try to slash a completed claim
        vm.warp(block.timestamp - 1 days); // Go back to within duration window
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Completed)
        );
        _executeSlash(claimIds, amounts);
    }

    /// @notice Test slashing from non-coverage-agent should revert
    function test_RevertWhen_slashClaims_notCoverageAgent() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        vm.warp(block.timestamp + 15 days);
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, attacker, address(coverageAgent))
        );
        eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();
    }

    /// @notice Fuzz test for slashing with various amounts
    /// @param slashAmountBps The slash amount as percentage of claim amount in basis points (1-10000)
    function testFuzz_slashClaims_variousAmounts(uint256 slashAmountBps) public {
        // Bound early to skip invalid cases before expensive setup
        slashAmountBps = bound(slashAmountBps, 1, 10000);

        // Use smaller stake amount for faster setup (still sufficient for 1000e6 claim)
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        uint256 slashAmount = (claimAmount * slashAmountBps) / 10000;
        if (slashAmount == 0) {
            slashAmount = 1;
        }

        // Get asset addresses
        address coverageAsset = coverageAgent.asset();
        address positionAsset = eigenCoverageProvider.position(positionId).asset;

        // Check balances before slashing
        uint256 contractCoverageBalanceBefore = IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentBalanceBefore = IERC20(coverageAsset).balanceOf(address(coverageAgent));
        uint256 contractPositionBalanceBefore = IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentCoordinatorBalanceBefore =
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()));

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify coverage agent has the same balance as before the slashing
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)),
            coverageAgentBalanceBefore,
            "Coverage agent should have exact same amount before and after slashing"
        );

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(IExampleCoverageAgent(coverageAgent).coordinator()))
                - coverageAgentCoordinatorBalanceBefore,
            slashAmount,
            "Coverage agent coordinator should receive exact slashed amount"
        );

        // Verify contract coverage asset balance returns to baseline (tokens transferred out)
        assertEq(
            IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond)),
            contractCoverageBalanceBefore,
            "Contract should transfer out all slashed coverage tokens"
        );

        // Verify position asset balance returns to baseline (no tokens left over)
        assertEq(
            IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond)),
            contractPositionBalanceBefore,
            "No position asset should remain after conversion to coverage asset"
        );
    }

    /// @notice Fuzz test for slashing timing (within valid window)
    /// @param timeOffset The time offset from claim creation in seconds (must be within duration)
    function testFuzz_slashClaims_timing(uint256 timeOffset) public {
        uint256 duration = 30 days;
        // Bound early to skip invalid cases before expensive setup
        timeOffset = bound(timeOffset, 1, duration);

        // Use smaller stake amount for faster setup (still sufficient for 1000e6 claim)
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, duration, 10e6, 0);
        uint256 createdAt = eigenCoverageProvider.claim(claimId).createdAt;

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        // Warp to the correct time based on createdAt
        vm.warp(createdAt + timeOffset);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Fuzz test for multiple claims slashing with various amounts
    /// @param numClaims Number of claims to create and slash (1-10)
    function testFuzz_slashClaims_multipleClaims(uint256 numClaims) public {
        // Bound early to skip invalid cases before expensive setup
        numClaims = bound(numClaims, 1, 10);

        // Calculate required stake: max claim is 1000e6 + (9 * 100e6) = 1900e6, use 2000e18 stake
        uint256 maxStakeNeeded = 2000e18;
        deal(rETH, staker, maxStakeNeeded);
        uint256 positionId = _setupSlashingPosition(maxStakeNeeded);
        uint256[] memory claimIds = new uint256[](numClaims);
        uint256[] memory amounts = new uint256[](numClaims);

        // Calculate total reward needed (sum of all rewards)
        uint256 totalReward = 0;
        for (uint256 i = 0; i < numClaims; i++) {
            totalReward += (10e6 + (i * 1e6));
        }

        // Ensure coverage agent has enough tokens
        deal(coverageAgent.asset(), address(coverageAgent), totalReward);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), totalReward);

        // Create multiple claims
        for (uint256 i = 0; i < numClaims; i++) {
            uint256 claimAmount = 1000e6 + (i * 100e6); // Varying amounts
            uint256 reward = 10e6 + (i * 1e6);
            claimIds[i] = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, reward);
            amounts[i] = claimAmount; // Slash full amount
        }
        vm.stopPrank();

        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        // Verify all claims are slashed
        for (uint256 i = 0; i < numClaims; i++) {
            assertEq(uint8(statuses[i]), uint8(CoverageClaimStatus.Slashed));
            assertEq(uint8(eigenCoverageProvider.claim(claimIds[i]).status), uint8(CoverageClaimStatus.Slashed));
            assertEq(eigenCoverageDiamond.claimSlashAmounts(claimIds[i]), amounts[i]);
        }
    }

    /// @notice Test slashing with slash coordinator (pending -> complete flow)
    function test_slashClaims_withCoordinator() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify claim backing before slashing
        int256 backingBeforeSlash = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeSlash, 0, "Claim should be fully backed before slashing");

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Warp time and expect ClaimSlashPending event (coordinator is set)
        vm.warp(block.timestamp + 15 days);

        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashPending(claimId, address(coordinator));

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);

        // Complete the slash through coordinator
        coordinator.setStatus(claimId, SlashCoordinationStatus.Passed);

        // Expect ClaimSlashed event when completing the slash
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        eigenCoverageProvider.completeSlash(claimId);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test completeSlash with invalid status should revert
    function test_RevertWhen_completeSlash_invalidStatus() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Try to complete slash without initiating it first
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Issued)
        );
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test completeSlash with coordinator status not completed should revert
    function test_RevertWhen_completeSlash_coordinatorNotCompleted() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Coordinator status is still Pending
        assertEq(
            uint8(coordinator.status(address(eigenCoverageDiamond), claimId)), uint8(SlashCoordinationStatus.Pending)
        );

        // Try to complete slash
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.SlashFailed.selector, claimId));
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test that slashing updates claim status correctly
    function test_slashClaims_statusUpdate() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify initial status
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Issued));

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Verify status updated to Slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test that slashing cannot be done twice on the same claim
    function test_RevertWhen_slashClaims_alreadySlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts, 15 days);

        // Second slash should fail
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        _executeSlash(claimIds, amounts);
    }

    /// @notice Test that _initiateSlash reverts when claim status is already Slashed
    function test_RevertWhen_initiateSlash_alreadySlashed() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // First slash with coordinator
        vm.warp(block.timestamp + 15 days);
        vm.startPrank(address(coverageAgent));
        eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Complete the slash through coordinator
        coordinator.setStatus(claimId, SlashCoordinationStatus.Passed);
        eigenCoverageProvider.completeSlash(claimId);

        // Verify claim is slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Attempt to complete slash again should revert with InvalidClaim
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        eigenCoverageProvider.completeSlash(claimId);
    }

    /// @notice Test that _initiateSlash runs immediately when coordinator returns Completed status
    function test_slashClaims_coordinatorCompletedImmediately() public {
        MockSlashCoordinatorImmediate coordinator = new MockSlashCoordinatorImmediate();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        // Warp time and expect ClaimSlashed event (coordinator returns Completed immediately)
        vm.warp(block.timestamp + 15 days);

        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimSlashed(claimId, 1000e6);

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Verify status is PendingSlash in return value (set before initiateSlash is called)
        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));

        // But the actual claim status should be Slashed (updated by _initiateSlash)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify slash amount was recorded
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);
    }

    function test_owner() public view {
        assertEq(IDiamondOwner(address(eigenCoverageDiamond)).owner(), address(this));
    }

    function test_setOwner() public {
        address newOwner = makeAddr("newOwner");
        IDiamondOwner(address(eigenCoverageDiamond)).setOwner(newOwner);
        assertEq(IDiamondOwner(address(eigenCoverageDiamond)).owner(), newOwner);
    }

    // ============ updateAVSMetadataURI Tests ============

    /// @notice Test that updateAVSMetadataURI successfully updates the metadata and emits the correct event
    function test_updateAVSMetadataURI() public {
        string memory newMetadataURI = "https://new-coverage.example.com/metadata.json";

        // Expect the AVSMetadataURIUpdated event from AllocationManager
        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), newMetadataURI);

        eigenServiceManager.updateAVSMetadataURI(newMetadataURI);
    }

    /// @notice Test that updateAVSMetadataURI can be called multiple times with different URIs
    function test_updateAVSMetadataURI_multipleTimes() public {
        string memory uri1 = "https://first-uri.example.com/metadata.json";
        string memory uri2 = "https://second-uri.example.com/metadata.json";

        // First update
        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), uri1);
        eigenServiceManager.updateAVSMetadataURI(uri1);

        // Second update
        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), uri2);
        eigenServiceManager.updateAVSMetadataURI(uri2);
    }

    /// @notice Test that updateAVSMetadataURI works with an empty string
    function test_updateAVSMetadataURI_emptyString() public {
        string memory emptyURI = "";

        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), emptyURI);

        eigenServiceManager.updateAVSMetadataURI(emptyURI);
    }

    /// @notice Test that updateAVSMetadataURI reverts when called by non-owner
    function test_RevertWhen_updateAVSMetadataURI_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        string memory newMetadataURI = "https://new-coverage.example.com/metadata.json";

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, address(this)));
        eigenServiceManager.updateAVSMetadataURI(newMetadataURI);
    }

    /// @notice Fuzz test for updateAVSMetadataURI with various URI strings
    function testFuzz_updateAVSMetadataURI(string calldata metadataURI) public {
        vm.expectEmit(true, false, false, true, eigenServiceManager.eigenAddresses().allocationManager);
        emit IAllocationManagerEvents.AVSMetadataURIUpdated(address(eigenCoverageDiamond), metadataURI);

        eigenServiceManager.updateAVSMetadataURI(metadataURI);
    }

    // ============ Reservation Tests ============

    /// @notice Helper to setup a position with reservations enabled
    function _setupPositionWithReservation(uint256 stakeAmount, uint256 maxReservationTime)
        internal
        returns (uint256 positionId)
    {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(stakeAmount);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: maxReservationTime,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        positionId = eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test reserving a claim
    function test_reserveClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));

        // Expect ClaimReserved event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimReserved(positionId, 0, 1000e6, 30 days);

        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Reserved));
        assertEq(claim.reward, 10e6);

        // Verify claim backing is positive (fully backed even for reservation)
        int256 backing = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backing, 0, "Reserved claim should be fully backed");
    }

    /// @notice Test that reservations are not allowed when maxReservationTime is 0
    function test_RevertWhen_reserveClaim_reservationsNotAllowed() public {
        // Create position without reservation enabled (maxReservationTime = 0)
        uint256 positionId = _setupSlashingPosition(10e18);

        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ReservationNotAllowed.selector, positionId));
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that issueClaim fails when strategy is no longer whitelisted after position creation
    function test_RevertWhen_issueClaim_strategyNotWhitelisted() public {
        // Setup position while strategy is whitelisted
        uint256 positionId = _setupSlashingPosition(10e18);

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Attempt to issue a claim - should fail because strategy is no longer whitelisted
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that reserveClaim fails when strategy is no longer whitelisted after position creation
    function test_RevertWhen_reserveClaim_strategyNotWhitelisted() public {
        // Setup position with reservation enabled while strategy is whitelisted
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        // Remove the strategy from the whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);
        assertFalse(eigenServiceManager.isStrategyWhitelisted(strategy));

        // Attempt to reserve a claim - should fail because strategy is no longer whitelisted
        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test converting a reserved claim to issued
    function test_convertReservedClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        int256 backingAfterReservation = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        // Approve tokens for the reward
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Expect ClaimIssued event
        vm.expectEmit(true, true, false, true);
        emit ICoverageProvider.ClaimIssued(positionId, claimId, 1000e6, 30 days);

        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);

        // Verify backing after conversion (should remain the same since amount didn't change)
        int256 backingAfterConversion = eigenCoverageProvider.claimBacking(claimId);
        assertEq(
            backingAfterConversion,
            backingAfterReservation,
            "Backing should remain same after conversion with same amount"
        );
    }

    /// @notice Test converting a reserved claim with smaller amount and duration
    function test_convertReservedClaim_partialConversion() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        int256 backingAfterReservation = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        // Approve tokens for a smaller reward (pro-rata)
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 5e6);

        // Convert with smaller amount and duration
        eigenCoverageProvider.convertReservedClaim(claimId, 500e6, 15 days, 5e6);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.amount, 500e6);
        assertEq(claim.duration, 15 days);

        // Verify backing increased after partial conversion (released 500e6 of coverage)
        int256 backingAfterConversion = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingAfterConversion, backingAfterReservation, "Backing should increase after partial conversion");
    }

    /// @notice Test that converting a claim fails if reservation has expired
    function test_RevertWhen_convertReservedClaim_expired() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        uint256 expiredAt = block.timestamp + 1 hours;

        // Warp past reservation time
        vm.warp(block.timestamp + 2 hours);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ReservationExpired.selector, claimId, expiredAt));
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that amount cannot exceed reserved amount
    function test_RevertWhen_convertReservedClaim_amountExceedsReserved() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.AmountExceedsReserved.selector, claimId, 2000e6, 1000e6)
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 2000e6, 30 days, 20e6);
        vm.stopPrank();
    }

    /// @notice Test that duration cannot exceed reserved duration
    function test_RevertWhen_convertReservedClaim_durationExceedsReserved() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.DurationExceedsReserved.selector, claimId, 60 days, 30 days)
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 60 days, 20e6);
        vm.stopPrank();
    }

    /// @notice Test closing an expired reservation
    function test_closeClaim_expiredReservation() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Verify backing after reservation
        int256 backingBeforeClose = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeClose, 0, "Reserved claim should be fully backed");

        // Warp past reservation time
        vm.warp(block.timestamp + 2 hours);

        // Anyone can close an expired reservation
        address anyone = makeAddr("anyone");
        vm.prank(anyone);

        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that non-coverage-agent cannot close a non-expired reservation
    function test_RevertWhen_closeClaim_reservationNotExpired() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 expiresAt = block.timestamp + 1 hours;
        vm.stopPrank();

        // Try to close before expiration as non-coverage-agent
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ClaimNotExpired.selector, claimId, expiresAt));
        eigenCoverageProvider.closeClaim(claimId);
    }

    /// @notice Test that coverage agent can close their own claim
    function test_closeClaim_byCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        int256 backingBeforeClose = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeClose, 0, "Reserved claim should be fully backed");

        // Coverage agent can close their own claim even before expiration
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test closing an issued claim by coverage agent
    function test_closeClaim_issuedClaim() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        // Create a reservation and convert it
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Verify backing after reservation
        int256 backingAfterReservation = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingAfterReservation, 0, "Reserved claim should be fully backed");

        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);

        // Verify backing after conversion
        int256 backingAfterConversion = eigenCoverageProvider.claimBacking(claimId);
        assertEq(
            backingAfterConversion,
            backingAfterReservation,
            "Backing should remain same after conversion with same amount"
        );

        // Coverage agent can close their own issued claim
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);
        vm.stopPrank();

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that anyone can close an issued claim after duration has elapsed
    function test_closeClaim_afterDurationElapsed() public {
        uint256 positionId = _setupSlashingPosition(10e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, 10e6, 0);

        // Verify backing after issuance
        int256 backingBeforeClose = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBeforeClose, 0, "Claim should be fully backed");

        // Warp past duration
        vm.warp(block.timestamp + 31 days);

        // Anyone can close an issued claim after duration has elapsed
        address anyone = makeAddr("anyone");
        vm.prank(anyone);

        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimClosed(claimId);

        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that closing an issued claim early with Full refundable policy refunds proportionally
    /// @dev Full means provider holds all rewards (no distribution over time), but refund is still time-based
    function test_closeClaim_earlyWithFullRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.Full);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Refundable.Full uses time-proportional refund on closeClaim (full refund only on liquidation).
        // 15 days remaining of 30 days = 50% refund.
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        uint256 expectedRefund = reward / 2;
        assertEq(
            coordinatorBalanceAfter - coordinatorBalanceBefore,
            expectedRefund,
            "Half of reward should be refunded for remaining time"
        );

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
        assertEq(claim.reward, reward - expectedRefund, "Reward should be reduced by refund amount");
    }

    /// @notice Test that closing an issued claim early with TimeWeighted refundable policy refunds proportionally
    function test_closeClaim_earlyWithTimeWeightedRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.TimeWeighted);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Verify time-weighted refund (50% remaining = 50% refund)
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        uint256 expectedRefund = reward / 2; // 15 days remaining out of 30 days
        assertEq(
            coordinatorBalanceAfter - coordinatorBalanceBefore, expectedRefund, "Half of reward should be refunded"
        );

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
    }

    /// @notice Test that closing an issued claim after duration elapsed with Full refundable policy does not refund
    function test_closeClaim_afterDurationElapsed_noRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.Full);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp past the claim duration
        vm.warp(block.timestamp + 31 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Anyone can close after duration elapsed
        eigenCoverageProvider.closeClaim(claimId);

        // Verify no refund was given (claim completed naturally)
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore, "No refund should be given after duration elapsed");

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
    }

    /// @notice Test that closing an issued claim early with None refundable policy does not refund
    function test_closeClaim_earlyWithNoRefund() public {
        uint256 positionId = _setupSlashingPosition(10e18, address(0), Refundable.None);
        uint256 reward = 10e6;
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 30 days, reward, 0);

        // Warp to halfway through the claim duration
        vm.warp(block.timestamp + 15 days);

        // Track coordinator balance before close (refund flows: provider -> agent -> coordinator)
        address coordinator = coverageAgent.coordinator();
        uint256 coordinatorBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(coordinator);

        // Coverage agent closes claim early
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Verify no refund was given
        uint256 coordinatorBalanceAfter = IERC20(coverageAgent.asset()).balanceOf(coordinator);
        assertEq(coordinatorBalanceAfter, coordinatorBalanceBefore, "No refund should be given with None policy");

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Completed));
        assertEq(claim.duration, 15 days, "Duration should reflect actual coverage time");
    }

    // ============ Claim Backing Tests ============

    /// @notice Test that backing decreases as multiple claims consume coverage
    function test_claimBacking_decreasesWithMultipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get total allocated coverage
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 30e6);

        // Issue first claim
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        int256 backing1 = eigenCoverageProvider.claimBacking(claimId1);
        assertGt(backing1, 0, "First claim should be fully backed");

        // Issue second claim - backing should decrease
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        int256 backing2 = eigenCoverageProvider.claimBacking(claimId2);
        assertGt(backing2, 0, "Second claim should still be backed");
        assertLt(backing2, backing1, "Backing should decrease with more claims");

        // Issue third claim - further decrease
        uint256 claimId3 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        int256 backing3 = eigenCoverageProvider.claimBacking(claimId3);
        assertGt(backing3, 0, "Third claim should still be backed");
        assertLt(backing3, backing2, "Backing should continue decreasing");

        vm.stopPrank();

        // All claims share the same backing since they're for the same operator/strategy/agent
        // Verify backing reflects remaining coverage
        uint256 totalClaimed = 1000e6 + 500e6 + 500e6;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(totalAllocated) - int256(totalClaimed);
        assertEq(backing3, expectedBacking, "Backing should equal allocated minus claimed");
    }

    /// @notice Test that backing is zero when claims exactly match allocated coverage
    function test_claimBacking_zeroWhenFullyUtilized() public {
        _setupwithAllocations();

        // Get allocated coverage amount
        uint256 totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Stake enough to cover exactly the claim amount
        address strategyAsset = address(_getTestStrategy().underlyingToken());
        address coverageAsset = address(coverageAgent.asset());
        (uint256 requiredStake,) = eigenPriceOracle.getQuote(totalAllocated, strategyAsset, coverageAsset);

        // Stake exactly what's needed (with small buffer for rounding)
        _stakeAndDelegateToOperator(requiredStake + 1e15);

        // Re-fetch allocated coverage after staking
        totalAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Issue claim for exactly the allocated amount
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, totalAllocated, 30 days, 10e6);
        vm.stopPrank();

        // Backing should be exactly zero (fully utilized)
        int256 backing = eigenCoverageProvider.claimBacking(claimId);
        assertEq(backing, 0, "Backing should be zero when fully utilized");
    }

    /// @notice Test that positionMaxAmount reflects remaining coverage correctly
    function test_positionMaxAmount_decreasesWithClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        uint256 initialMaxAmount = eigenCoverageProvider.positionMaxAmount(positionId);
        assertGt(initialMaxAmount, 0, "Initial max amount should be positive");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        // Issue a claim
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        uint256 maxAmountAfterClaim = eigenCoverageProvider.positionMaxAmount(positionId);
        assertEq(maxAmountAfterClaim, initialMaxAmount - 1000e6, "Max amount should decrease by claimed amount");

        // Issue another claim
        eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);

        uint256 maxAmountAfterSecondClaim = eigenCoverageProvider.positionMaxAmount(positionId);
        assertEq(maxAmountAfterSecondClaim, initialMaxAmount - 1500e6, "Max amount should decrease by total claimed");
        vm.stopPrank();
    }

    /// @notice Test backing increases when claims are closed
    function test_claimBacking_increasesWhenClaimsClosed() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);

        // Issue two claims
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);

        int256 backingWithBothClaims = eigenCoverageProvider.claimBacking(claimId1);

        // Close the second claim
        eigenCoverageProvider.closeClaim(claimId2);

        // Backing should increase for remaining claims
        int256 backingAfterClose = eigenCoverageProvider.claimBacking(claimId1);
        assertGt(backingAfterClose, backingWithBothClaims, "Backing should increase when claims are closed");
        assertEq(backingAfterClose, backingWithBothClaims + 500e6, "Backing should increase by closed claim amount");
        vm.stopPrank();
    }

    /// @notice Test that InsufficientCoverageAvailable error includes correct deficit amount
    function test_RevertWhen_claimBacking_insufficientCoverage_correctDeficit() public {
        _setupwithAllocations();

        // Stake a small amount to get limited coverage
        _stakeAndDelegateToOperator(1e16); // Small stake

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        uint256 allocatedCoverage = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Try to claim more than allocated
        uint256 excessiveClaimAmount = allocatedCoverage + 1000e6;

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // The deficit should be exactly the amount over the allocation
        uint256 expectedDeficit = excessiveClaimAmount - allocatedCoverage;
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InsufficientCoverageAvailable.selector, expectedDeficit)
        );
        eigenCoverageProvider.issueClaim(positionId, excessiveClaimAmount, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that backing becomes deficient (negative) when operator deallocates after claim is issued
    function test_claimBacking_deficientAfterDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocated coverage
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertGt(initialAllocated, 0, "Should have initial allocation");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);

        // Issue a claim while fully backed
        uint256 claimAmount = 1000e6;
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, 10e6);
        vm.stopPrank();

        // Verify claim is initially backed
        int256 backingBefore = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBefore, 0, "Claim should be backed initially");

        // Operator deallocates all coverage (sets magnitude to 0)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0; // Deallocate

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay (14 days worth of blocks)
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue to finalize the deallocation
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Verify allocation is now 0
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertEq(allocatedAfterDeallocation, 0, "Allocation should be zero after deallocation");

        // Now backing should be negative (deficient)
        int256 backingAfter = eigenCoverageProvider.claimBacking(claimId);
        assertLt(backingAfter, 0, "Backing should be negative (deficient) after deallocation");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(backingAfter, -int256(claimAmount), "Backing deficit should equal claimed amount");
    }

    /// @notice Test that backing becomes partially deficient after partial deallocation
    function test_claimBacking_partialDeficitAfterPartialDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocation so we can calculate a claim amount that will be deficient after 50% deallocation
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Claim 75% of the initial allocation - after 50% deallocation, this will be 25% deficient
        uint256 claimAmount = (initialAllocated * 75) / 100;

        // Calculate minimum reward: (amount * minRate * duration) / (10000 * 365 days)
        // Position minRate is 100, duration is 30 days
        uint256 minReward = (claimAmount * 100 * 30 days) / (10000 * 365 days) + 1;

        vm.startPrank(address(coverageAgent));
        deal(coverageAgent.asset(), address(coverageAgent), minReward);
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), minReward);

        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, minReward);
        vm.stopPrank();

        // Verify claim is initially backed
        int256 backingBefore = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBefore, 0, "Claim should be backed initially");

        // Operator partially deallocates (reduces magnitude to 50%)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0.5e18; // Reduce to 50% of original 1e18

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Get the new allocated amount (should be ~50% of initial)
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Verify deallocation occurred (allocation should be roughly half)
        assertLt(allocatedAfterDeallocation, initialAllocated, "Allocation should have decreased");

        // After 50% deallocation: allocation is ~50% of initial, claim is 75% of initial
        // So claim (75%) > allocation (50%), resulting in a deficit of ~25% of initial
        int256 backingAfter = eigenCoverageProvider.claimBacking(claimId);

        // Backing should be negative (deficient)
        assertLt(backingAfter, 0, "Backing should be negative after partial deallocation");

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(allocatedAfterDeallocation) - int256(claimAmount);
        assertEq(backingAfter, expectedBacking, "Backing deficit should match expected");
    }

    /// @notice Test that backing remains positive after partial deallocation when claim is small
    function test_claimBacking_remainsPositiveAfterPartialDeallocation() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        // Get initial allocation
        uint256 initialAllocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // Claim only 25% of the initial allocation - after 50% deallocation, this will still be backed
        uint256 claimAmount = (initialAllocated * 25) / 100;

        // Calculate minimum reward: (amount * minRate * duration) / (10000 * 365 days)
        uint256 minReward = (claimAmount * 100 * 30 days) / (10000 * 365 days) + 1;

        vm.startPrank(address(coverageAgent));
        deal(coverageAgent.asset(), address(coverageAgent), minReward);
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), minReward);

        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, claimAmount, 30 days, minReward);
        vm.stopPrank();

        // Verify claim is initially backed
        int256 backingBefore = eigenCoverageProvider.claimBacking(claimId);
        assertGt(backingBefore, 0, "Claim should be backed initially");

        // Operator partially deallocates (reduces magnitude to 50%)
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 0.5e18; // Reduce to 50% of original 1e18

        operator.allocate(address(eigenCoverageDiamond), address(coverageAgent), strategyAddresses, magnitudes);

        // Roll forward past the deallocation delay
        uint32 deallocationDelay = _getAllocationManager().DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Clear the deallocation queue
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _getTestStrategy();
        uint16[] memory numToClear = new uint16[](1);
        numToClear[0] = 1;
        _getAllocationManager().clearDeallocationQueue(address(operator), strategies, numToClear);

        // Get the new allocated amount (should be ~50% of initial)
        uint256 allocatedAfterDeallocation = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );

        // After 50% deallocation: allocation is ~50% of initial, claim is 25% of initial
        // So allocation (50%) > claim (25%), backing remains positive
        int256 backingAfter = eigenCoverageProvider.claimBacking(claimId);

        // Backing should still be positive
        assertGt(backingAfter, 0, "Backing should remain positive when allocation > claim");

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedBacking = int256(allocatedAfterDeallocation) - int256(claimAmount);
        assertEq(backingAfter, expectedBacking, "Backing should match expected");
    }

    // ============ claimTotalSlashAmount Tests ============

    /// @notice Test claimTotalSlashAmount returns correct amount after slashing
    function test_claimTotalSlashAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 500e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns the correct amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Test claimTotalSlashAmount returns 0 for non-existent claim
    function test_claimTotalSlashAmount_nonExistentClaim() public view {
        // Query slash amount for a claim ID that doesn't exist
        uint256 nonExistentClaimId = 999;
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(nonExistentClaimId), 0);
    }

    /// @notice Test claimTotalSlashAmount returns 0 for claim that hasn't been slashed
    function test_claimTotalSlashAmount_notSlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Verify claimTotalSlashAmount returns 0 before any slashing
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test claimTotalSlashAmount returns correct amount for partial slash
    function test_claimTotalSlashAmount_partialSlash() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Slash only 25% of the claim amount
        uint256 slashAmount = 250e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns exactly the partial amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Test claimTotalSlashAmount returns correct amount for exact (full) slash
    function test_claimTotalSlashAmount_exactAmount() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        // Slash the full claim amount
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, claimAmount);

        _executeSlash(claimIds, amounts);

        // Verify claimTotalSlashAmount returns the full claim amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), claimAmount);
    }

    /// @notice Test claimTotalSlashAmount returns correct amounts for multiple claims
    function test_claimTotalSlashAmount_multipleClaims() public {
        deal(rETH, staker, 2000e18);
        uint256 positionId = _setupSlashingPosition(2000e18);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 20e6);
        uint256 claimId1 = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.issueClaim(positionId, 500e6, 30 days, 5e6);
        vm.stopPrank();

        // Verify both claims have 0 slash amount before slashing
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId1), 0);
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId2), 0);

        uint256 slashAmount1 = 750e6;
        uint256 slashAmount2 = 300e6;

        uint256[] memory claimIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        claimIds[0] = claimId1;
        claimIds[1] = claimId2;
        amounts[0] = slashAmount1;
        amounts[1] = slashAmount2;

        _executeSlash(claimIds, amounts);

        // Verify each claim has its correct slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId1), slashAmount1);
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId2), slashAmount2);
    }

    /// @notice Test claimTotalSlashAmount with slash coordinator (PendingSlash state)
    function test_claimTotalSlashAmount_withSlashCoordinator() public {
        MockSlashCoordinator mockCoordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(mockCoordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        uint256 slashAmount = 500e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);

        vm.startPrank(address(coverageAgent));
        CoverageClaimStatus[] memory statuses = eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        // Verify status is PendingSlash
        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));

        // Verify claimTotalSlashAmount is set even in PendingSlash state
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);

        // Complete the slash via coordinator
        mockCoordinator.setStatus(claimId, SlashCoordinationStatus.Passed);
        eigenCoverageProvider.completeSlash(claimId);

        // Verify slash amount remains the same after completion
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    /// @notice Fuzz test for claimTotalSlashAmount with various amounts
    /// @param slashAmountBps The slash amount as percentage of claim amount in basis points (1-10000)
    function testFuzz_claimTotalSlashAmount(uint256 slashAmountBps) public {
        // Bound early to skip invalid cases before expensive setup
        slashAmountBps = bound(slashAmountBps, 1, 10000);

        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimAmount = 1000e6;
        uint256 claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        // Calculate slash amount from basis points
        uint256 slashAmount = (claimAmount * slashAmountBps) / 10000;
        if (slashAmount == 0) slashAmount = 1; // Ensure at least 1 wei

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        _executeSlash(claimIds, amounts, 15 days);

        // Verify claimTotalSlashAmount returns the exact slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount);
    }

    // ============ repaySlashedClaim Tests ============

    /// @notice Helper to set up a slashed claim for repayment tests
    /// @param stakeAmount Amount to stake and delegate to operator
    /// @param claimAmount Amount of coverage to claim
    /// @param slashAmount Amount to slash from the claim
    /// @return positionId The created position ID
    /// @return claimId The created and slashed claim ID
    function _setupSlashedClaim(uint256 stakeAmount, uint256 claimAmount, uint256 slashAmount)
        internal
        returns (uint256 positionId, uint256 claimId)
    {
        positionId = _setupSlashingPosition(stakeAmount);
        claimId = _createAndApproveClaim(positionId, claimAmount, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        _executeSlash(claimIds, amounts, 15 days);

        // Verify claim is now slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test repaying a slashed claim fully
    function test_repaySlashedClaim() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);

        // Approve diamond to spend tokens
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);

        // Expect ClaimRepaid event (full repayment - emitted without amount)
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimRepaid(claimId);

        // Expect ClaimRepayment event (emitted on every repayment with amount)
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, slashAmount);

        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim status is now Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is cleared
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test partial repayment of a slashed claim
    function test_repaySlashedClaim_partialRepayment() public {
        uint256 slashAmount = 500e6;
        uint256 partialRepayment = 200e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), partialRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), partialRepayment);

        // Expect ClaimRepayment event (partial repayment - no ClaimRepaid event)
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, partialRepayment);

        eigenCoverageProvider.repaySlashedClaim(claimId, partialRepayment);
        vm.stopPrank();

        // Verify claim status remains Slashed (not fully repaid)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify remaining slash amount
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount - partialRepayment);
    }

    /// @notice Test multiple partial repayments leading to full repayment
    function test_repaySlashedClaim_multiplePartialRepayments() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // First partial repayment
        uint256 firstRepayment = 200e6;
        deal(coverageAgent.asset(), address(coverageAgent), firstRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), firstRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, firstRepayment);
        vm.stopPrank();

        // Verify still slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 300e6);

        // Second partial repayment
        uint256 secondRepayment = 150e6;
        deal(coverageAgent.asset(), address(coverageAgent), secondRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), secondRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, secondRepayment);
        vm.stopPrank();

        // Verify still slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 150e6);

        // Final repayment (remaining amount)
        uint256 finalRepayment = 150e6;
        deal(coverageAgent.asset(), address(coverageAgent), finalRepayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), finalRepayment);
        eigenCoverageProvider.repaySlashedClaim(claimId, finalRepayment);
        vm.stopPrank();

        // Verify now fully repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test overpayment is allowed (amount > slashAmount)
    function test_repaySlashedClaim_overpayment() public {
        uint256 slashAmount = 500e6;
        uint256 overpayment = 700e6; // More than slash amount
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to overpay
        deal(coverageAgent.asset(), address(coverageAgent), overpayment);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), overpayment);

        // Expect ClaimRepaid event (full repayment - overpayment counts as full)
        vm.expectEmit(true, false, false, false);
        emit ICoverageProvider.ClaimRepaid(claimId);

        // Expect ClaimRepayment event with full overpayment amount
        vm.expectEmit(true, false, false, true);
        emit ICoverageProvider.ClaimRepayment(claimId, overpayment);

        eigenCoverageProvider.repaySlashedClaim(claimId, overpayment);
        vm.stopPrank();

        // Verify claim status is Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is cleared (not negative)
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test repayment reverts when claim is not slashed
    function test_RevertWhen_repaySlashedClaim_notSlashed() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Claim is Issued, not Slashed
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Issued));

        deal(coverageAgent.asset(), address(coverageAgent), 100e6);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 100e6);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Issued)
        );
        eigenCoverageProvider.repaySlashedClaim(claimId, 100e6);
        vm.stopPrank();
    }

    /// @notice Test repayment reverts when caller is not the coverage agent
    function test_RevertWhen_repaySlashedClaim_notCoverageAgent() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        address randomCaller = makeAddr("randomCaller");
        deal(coverageAgent.asset(), randomCaller, slashAmount);

        vm.startPrank(randomCaller);
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);

        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, randomCaller, address(coverageAgent))
        );
        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();
    }

    /// @notice Test repayment reverts when claim is already repaid
    /// @notice Test additional repayment after claim is already repaid
    function test_repaySlashedClaim_additionalRepaymentAfterRepaid() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // First repayment - full amount
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim is Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Additional repayment after already being Repaid should succeed
        uint256 additionalAmount = 100e6;
        deal(coverageAgent.asset(), address(coverageAgent), additionalAmount);
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), additionalAmount);

        // Record logs to verify ClaimRepaid is NOT emitted
        vm.recordLogs();

        eigenCoverageProvider.repaySlashedClaim(claimId, additionalAmount);
        vm.stopPrank();

        // Get recorded logs and verify ClaimRepaid was NOT emitted
        bytes32 claimRepaidSelector = ICoverageProvider.ClaimRepaid.selector;
        bytes32 claimRepaymentSelector = ICoverageProvider.ClaimRepayment.selector;

        bool foundClaimRepaid = false;
        bool foundClaimRepayment = false;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == claimRepaidSelector) {
                foundClaimRepaid = true;
            }
            if (logs[i].topics[0] == claimRepaymentSelector) {
                foundClaimRepayment = true;
            }
        }

        // ClaimRepaid should NOT be emitted for additional repayments
        assertFalse(foundClaimRepaid, "ClaimRepaid should not be emitted for additional repayments");

        // ClaimRepayment should be emitted
        assertTrue(foundClaimRepayment, "ClaimRepayment should be emitted for additional repayments");

        // Verify claim status remains Repaid
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));

        // Verify slash amount is still 0 (already cleared from first full repayment)
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Test that repayment transfers tokens from coverage agent to diamond
    function test_repaySlashedClaim_tokenTransfer() public {
        uint256 slashAmount = 500e6;
        uint256 repayAmount = 300e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), repayAmount);

        uint256 coverageAgentBalanceBefore = IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent));

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), repayAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, repayAmount);
        vm.stopPrank();

        // Verify tokens were transferred from coverage agent
        assertEq(
            IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent)), coverageAgentBalanceBefore - repayAmount
        );

        // Note: Diamond balance may not increase by full amount due to reward submission
        // The tokens are used to submit operator rewards, so we just verify they left the coverage agent
    }

    /// @notice Test repayment with exact slash amount (boundary condition)
    function test_repaySlashedClaim_exactAmount() public {
        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(1000e18, 1000e6, slashAmount);

        // Give coverage agent exact tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), slashAmount);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), slashAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, slashAmount);
        vm.stopPrank();

        // Verify claim status is Repaid (amount >= slashAmount)
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
        assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
    }

    /// @notice Fuzz test for repaySlashedClaim with various repayment amounts
    /// @param repaymentBps The repayment amount as percentage of slash amount in basis points (1-15000)
    function testFuzz_repaySlashedClaim(uint256 repaymentBps) public {
        // Bound early to include overpayment scenarios (up to 150% of slash amount)
        repaymentBps = bound(repaymentBps, 1, 15000);

        uint256 slashAmount = 500e6;
        (, uint256 claimId) = _setupSlashedClaim(100e18, 1000e6, slashAmount);

        // Calculate repayment amount from basis points
        uint256 repayAmount = (slashAmount * repaymentBps) / 10000;
        if (repayAmount == 0) repayAmount = 1; // Ensure at least 1 wei

        // Give coverage agent tokens to repay
        deal(coverageAgent.asset(), address(coverageAgent), repayAmount);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), repayAmount);
        eigenCoverageProvider.repaySlashedClaim(claimId, repayAmount);
        vm.stopPrank();

        // Verify results based on repayment amount
        if (repayAmount >= slashAmount) {
            // Full repayment or overpayment
            assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Repaid));
            assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), 0);
        } else {
            // Partial repayment
            assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
            assertEq(eigenCoverageProvider.claimTotalSlashAmount(claimId), slashAmount - repayAmount);
        }
    }

    // ============ EigenCoverageProviderFacet Branch Coverage Tests ============

    // --- onIsRegistered (line 35) ---

    /// @notice Test that onIsRegistered reverts if coverage agent is already registered
    function test_RevertWhen_onIsRegistered_alreadyRegistered() public {
        // coverageAgent is already registered in setUp via coverageAgent.registerCoverageProvider(...)
        // Calling onIsRegistered again from the same coverage agent should revert
        vm.prank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(IEigenServiceManager.CoverageAgentAlreadyRegistered.selector));
        eigenCoverageProvider.onIsRegistered();
    }

    // --- createPosition validation branches (lines 62, 63, 69, 75, 77) ---

    /// @notice Test that createPosition reverts when expiryTimestamp is in the past
    function test_RevertWhen_createPosition_expiredTimestamp() public {
        _setupwithAllocations();

        uint256 pastTimestamp = block.timestamp - 1;
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: pastTimestamp,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.TimestampInvalid.selector, pastTimestamp));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when minRate exceeds 10000
    function test_RevertWhen_createPosition_invalidMinRate() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 10001,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.MinRateInvalid.selector, uint16(10001)));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when asset has no mapped strategy (strategy == address(0))
    function test_RevertWhen_createPosition_unmappedAsset() public {
        _setupwithAllocations();

        // Use an asset that has no strategy mapping (e.g., WETH which is not mapped in setUp)
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: WETH, // No strategy mapped for WETH
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, address(0)));
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when caller doesn't have operator permissions
    function test_RevertWhen_createPosition_notAuthorized() public {
        _setupwithAllocations();

        // Create a position using an unauthorized address (not the operator handler)
        address unauthorized = makeAddr("unauthorized");
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IEigenServiceManager.NotOperatorAuthorized.selector, address(operator), unauthorized)
        );
        eigenCoverageProvider.createPosition(data, "");
    }

    /// @notice Test that createPosition reverts when strategy is not whitelisted
    function test_RevertWhen_createPosition_strategyNotWhitelisted() public {
        _setupwithAllocations();

        // Remove the strategy from whitelist
        address strategy = address(_getTestStrategy());
        eigenServiceManager.setStrategyWhitelist(strategy, false);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });

        vm.expectRevert(abi.encodeWithSelector(IEigenOperatorProxy.StrategyNotWhitelisted.selector, strategy));
        eigenCoverageProvider.createPosition(data, "");
    }

    // --- reserveClaim validation branches (lines 160, 163) ---

    /// @notice Test that reserveClaim reverts with zero amount
    function test_RevertWhen_reserveClaim_zeroAmount() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.prank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ZeroAmount.selector));
        eigenCoverageProvider.reserveClaim(positionId, 0, 30 days, 10e6);
    }

    /// @notice Test that reserveClaim reverts when caller is not the coverage agent
    function test_RevertWhen_reserveClaim_notCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, unauthorized, address(coverageAgent))
        );
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
    }

    // --- convertReservedClaim validation branches (lines 203, 206, 222, 226) ---

    /// @notice Test that convertReservedClaim reverts when claim is not in Reserved status
    function test_RevertWhen_convertReservedClaim_notReserved() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(10e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        // Issue a regular claim (status = Issued, not Reserved)
        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);

        // Try to convert an Issued claim (not Reserved)
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ClaimNotReserved.selector, claimId));
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
        vm.stopPrank();
    }

    /// @notice Test that convertReservedClaim reverts when caller is not the coverage agent
    function test_RevertWhen_convertReservedClaim_notCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.prank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // Try to convert from an unauthorized address
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, unauthorized, address(coverageAgent))
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
    }

    /// @notice Test that convertReservedClaim reverts when amount is zero
    function test_RevertWhen_convertReservedClaim_zeroAmount() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.ZeroAmount.selector));
        eigenCoverageProvider.convertReservedClaim(claimId, 0, 30 days, 0);
        vm.stopPrank();
    }

    /// @notice Test that convertReservedClaim reverts when reward is insufficient
    function test_RevertWhen_convertReservedClaim_insufficientReward() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.startPrank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        // The minimum reward for 1000e6 coverage at 100 bps for 30 days:
        // minReward = (1000e6 * 100 * 30 days) / (10000 * 365 days)
        // Try with a very small reward that doesn't meet the minimum
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 1);
        vm.expectRevert(); // InsufficientReward
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 1);
        vm.stopPrank();
    }

    // --- closeClaim validation branch (line 269) ---

    /// @notice Test that closeClaim reverts when claim status is neither Reserved nor Issued
    function test_RevertWhen_closeClaim_invalidStatus() public {
        uint256 positionId = _setupSlashingPosition(100e18);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Slash the claim first to change its status to Slashed
        uint256[] memory claimIds = new uint256[](1);
        claimIds[0] = claimId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500e6;
        _executeSlash(claimIds, amounts);

        // Verify claim is now Slashed
        CoverageClaim memory slashedClaim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(slashedClaim.status), uint8(CoverageClaimStatus.Slashed));

        // Try to close a Slashed claim - should revert
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId, CoverageClaimStatus.Slashed)
        );
        eigenCoverageProvider.closeClaim(claimId);
    }

    // --- liquidateClaim (line 313-315) ---

    /// @notice Test that liquidateClaim reverts with NotImplemented
    function test_RevertWhen_liquidateClaim_notImplemented() public {
        vm.expectRevert();
        eigenCoverageProvider.liquidateClaim(0);
    }

    // ============ EigenServiceManagerFacet Branch Coverage Tests ============

    // --- registerOperator ---

    /// @notice Test that registerOperator reverts with InvalidAVS when avs is not this contract
    function test_RevertWhen_registerOperator_invalidAVS() public {
        address randomAVS = makeAddr("randomAVS");
        uint32[] memory operatorSetIds = new uint32[](0);

        vm.expectRevert(abi.encodeWithSelector(IEigenServiceManager.InvalidAVS.selector, randomAVS));
        eigenServiceManager.registerOperator(address(this), randomAVS, operatorSetIds, "");
    }

    /// @notice Test that registerOperator reverts when called by the delegation manager
    function test_RevertWhen_registerOperator_calledByDelegationManager() public {
        address delegationManager = eigenServiceManager.eigenAddresses().delegationManager;
        uint32[] memory operatorSetIds = new uint32[](0);

        vm.prank(delegationManager);
        vm.expectRevert("Not delegation manager");
        eigenServiceManager.registerOperator(address(this), address(eigenCoverageDiamond), operatorSetIds, "");
    }

    /// @notice Test that registerOperator succeeds when called by non-delegation-manager with correct AVS
    function test_registerOperator_succeeds() public {
        uint32[] memory operatorSetIds = new uint32[](0);
        // This function just validates, should not revert
        eigenServiceManager.registerOperator(address(this), address(eigenCoverageDiamond), operatorSetIds, "");
    }

    // --- captureRewards with Refundable.Full ---

    /// @notice Test captureRewards returns (0,0,...) for Refundable.Full when claim is NOT yet Completed
    function test_captureRewards_refundableFull_notCompleted() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        // Create position with Refundable.Full
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Warp partway through the claim (still Issued, not Completed)
        vm.warp(block.timestamp + 15 days);

        // captureRewards should return 0 for Full refundable when claim is still Issued
        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0, "Amount should be 0 for Full refundable when not Completed");
        assertEq(duration, 0, "Duration should be 0 for Full refundable when not Completed");
        assertEq(distributionStartTime, 0, "Distribution start time should be 0 for Full refundable when not Completed");
    }

    /// @notice Test captureRewards returns full reward for Refundable.Full when claim IS Completed
    function test_captureRewards_refundableFull_completed() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        // Create position with Refundable.Full
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Warp past the claim duration and close it so status becomes Completed
        vm.warp(block.timestamp + 31 days);
        eigenCoverageProvider.closeClaim(claimId);

        CoverageClaim memory _claim = eigenCoverageProvider.claim(claimId);
        assertEq(uint8(_claim.status), uint8(CoverageClaimStatus.Completed), "Claim should be Completed after close");

        // captureRewards should now return the full reward
        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6, "Amount should equal full reward for Full refundable when Completed");
    }

    /// @notice Test captureRewards distributes the reduced reward after early close with Full policy
    function test_captureRewards_refundableFull_afterEarlyClose() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        uint256 reward = 10e6;

        // Create position with Refundable.Full
        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), reward);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, reward);
        vm.stopPrank();

        // Close early at halfway — time-proportional refund (50%)
        vm.warp(block.timestamp + 15 days);
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.closeClaim(claimId);

        // Verify reward was reduced by the refund amount (50%)
        CoverageClaim memory _claim = eigenCoverageProvider.claim(claimId);
        assertEq(_claim.reward, reward / 2, "Reward should be reduced by refund amount");
        assertEq(uint8(_claim.status), uint8(CoverageClaimStatus.Completed));

        // captureRewards should distribute the remaining reward (50%) now that status is Completed
        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, reward / 2, "captureRewards should distribute remaining reward after early close");
    }

    /// @notice Test captureRewards returns 0 immediately after claim creation (elapsedDuration == 0 for non-Full)
    function test_captureRewards_zeroElapsedDuration() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Call captureRewards in the same block as claim creation (elapsedDuration == 0)
        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0, "Amount should be 0 when elapsed duration is 0");
        assertEq(duration, 0, "Duration should be 0 when elapsed duration is 0");
        // distributionStartTime should equal the claim creation timestamp (lastDistributedTimestamp)
        assertEq(distributionStartTime, uint32(block.timestamp), "Should return the claim creation timestamp");
    }

    // --- submitOperatorReward external access control ---

    /// @notice Test that submitOperatorReward reverts when called externally
    function test_RevertWhen_submitOperatorReward_notInternal() public {
        // Pre-compute parameters before expectRevert (these involve external calls)
        IStrategy strategy = _getTestStrategy();
        address asset = coverageAgent.asset();

        vm.expectRevert("Only internal calls");
        eigenServiceManager.submitOperatorReward(
            address(operator),
            strategy,
            IERC20v5(asset),
            1e6,
            0,
            1 days,
            "Test reward"
        );
    }

    // --- slashOperator external access control ---

    /// @notice Test that slashOperator reverts when called externally
    function test_RevertWhen_slashOperator_notInternal() public {
        // Pre-compute parameters before expectRevert
        address strategy = address(_getTestStrategy());

        vm.expectRevert("Only internal calls");
        eigenServiceManager.slashOperator(
            address(operator), strategy, address(coverageAgent), 100e6
        );
    }

    // --- ensureAllocations ---

    /// @notice Test that ensureAllocations reverts when operator has zero allocation
    function test_RevertWhen_ensureAllocations_notAllocated() public {
        // Register coverage agent with operator but do NOT allocate any strategy magnitude
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageDiamond), address(coverageAgent), 0);

        // Strategy exists in the operator set but operator has 0 magnitude
        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.NotAllocated.selector,
                address(operator),
                address(_getTestStrategy()),
                address(coverageAgent)
            )
        );
        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(_getTestStrategy()));
    }

    /// @notice Test that ensureAllocations succeeds when operator has allocations
    function test_ensureAllocations_succeeds() public {
        _setupwithAllocations();

        // Should not revert since operator has allocations
        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(_getTestStrategy()));
    }

    /// @notice Test that ensureAllocations adds strategy to operator set if not already present
    function test_ensureAllocations_addsStrategyToSet() public {
        // Register coverage agent and allocate
        _setupwithAllocations();

        // Create a second mock strategy with a different underlying token
        MockStrategy newStrategy = new MockStrategy(WETH);
        eigenServiceManager.setStrategyWhitelist(address(newStrategy), true);

        // Verify strategy is not yet in the operator set by calling ensureAllocations
        // It should revert with NotAllocated because the operator hasn't allocated to this new strategy
        vm.expectRevert(
            abi.encodeWithSelector(
                IEigenServiceManager.NotAllocated.selector,
                address(operator),
                address(newStrategy),
                address(coverageAgent)
            )
        );
        eigenServiceManager.ensureAllocations(address(operator), address(coverageAgent), address(newStrategy));
    }

    // --- setStrategyWhitelist access control ---

    /// @notice Test that setStrategyWhitelist reverts when called by non-owner
    function test_RevertWhen_setStrategyWhitelist_notOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.NotContractOwner.selector, nonOwner, address(this)));
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
    }

    // --- captureRewards multiple captures with TimeWeighted ---

    /// @notice Test that captureRewards accumulates correctly over multiple calls with TimeWeighted
    function test_captureRewards_timeWeighted_multipleCaptures() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        uint256 totalCaptured;

        // Capture at 10 days (1/3 of duration)
        vm.warp(block.timestamp + 10 days);
        (uint256 amount1,,) = eigenServiceManager.captureRewards(claimId);
        totalCaptured += amount1;
        assertApproxEqAbs(amount1, 3333333, 1, "First capture should be ~1/3 of reward");

        // Capture at 20 days (2/3 of duration)
        vm.warp(block.timestamp + 10 days);
        (uint256 amount2,,) = eigenServiceManager.captureRewards(claimId);
        totalCaptured += amount2;
        assertApproxEqAbs(amount2, 3333333, 1, "Second capture should be ~1/3 of reward");

        // Capture after duration ends (30 days)
        vm.warp(block.timestamp + 10 days);
        (uint256 amount3,,) = eigenServiceManager.captureRewards(claimId);
        totalCaptured += amount3;

        // Total captured should equal the full reward
        assertEq(totalCaptured, 10e6, "Total captured should equal full reward");
    }

    // --- captureRewards with None refundable, partial time ---

    /// @notice Test captureRewards with Refundable.None captures incrementally
    function test_captureRewards_refundableNone_fullCaptureImmediate() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(1000e18);

        CoveragePosition memory data = CoveragePosition({
            coverageAgent: address(coverageAgent),
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0),
            maxReservationTime: 0,
            operatorId: bytes32(uint256(uint160(address(operator))))
        });
        uint256 positionId = eigenCoverageProvider.createPosition(data, "");

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        // Capture at 15 days (halfway) — None policy grants full reward immediately
        vm.warp(block.timestamp + 15 days);
        (uint256 amount,,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6, "Should capture full reward regardless of elapsed time for None policy");

        // Capture again at the same block should return 0 (already fully distributed)
        (uint256 amountAgain, uint32 durationAgain,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amountAgain, 0, "Second capture in same block should return 0");
        assertEq(durationAgain, 0, "Duration should be 0 for second capture in same block");
    }

    // --- coverageAllocated view function ---

    /// @notice Test that coverageAllocated returns correct value after staking
    function test_coverageAllocated_returnsCorrectValue() public {
        _setupwithAllocations();
        _stakeAndDelegateToOperator(10e18);

        uint256 allocated = eigenServiceManager.coverageAllocated(
            address(operator), address(_getTestStrategy()), address(coverageAgent)
        );
        assertGt(allocated, 0, "Coverage allocated should be greater than 0 after staking and allocation");
    }

    // --- getOperatorSetId view function ---

    /// @notice Test that getOperatorSetId returns correct operator set ID after registration
    function test_getOperatorSetId_afterRegistration() public {
        _setupwithAllocations();

        uint32 operatorSetId = eigenServiceManager.getOperatorSetId(address(coverageAgent));
        // Should be > 0 since the coverage agent has been registered
        assertGt(operatorSetId, 0, "Operator set ID should be greater than 0");
    }

    /// @notice Test that getOperatorSetId returns 0 for unregistered coverage agent
    function test_getOperatorSetId_unregistered() public {
        address unregistered = makeAddr("unregistered");
        uint32 operatorSetId = eigenServiceManager.getOperatorSetId(unregistered);
        assertEq(operatorSetId, 0, "Operator set ID should be 0 for unregistered agent");
    }

    // --- eigenAddresses view function ---

    /// @notice Test that eigenAddresses returns valid non-zero addresses
    function test_eigenAddresses_returnsValidAddresses() public view {
        EigenAddresses memory addrs = eigenServiceManager.eigenAddresses();
        assertTrue(addrs.allocationManager != address(0), "Allocation manager should not be zero");
        assertTrue(addrs.delegationManager != address(0), "Delegation manager should not be zero");
        assertTrue(addrs.strategyManager != address(0), "Strategy manager should not be zero");
        assertTrue(addrs.rewardsCoordinator != address(0), "Rewards coordinator should not be zero");
        assertTrue(addrs.permissionController != address(0), "Permission controller should not be zero");
    }

    // --- isStrategyWhitelisted view function ---

    /// @notice Test isStrategyWhitelisted returns false for non-whitelisted strategy
    function test_isStrategyWhitelisted_nonWhitelisted() public {
        address randomStrategy = makeAddr("randomStrategy");
        assertFalse(
            eigenServiceManager.isStrategyWhitelisted(randomStrategy),
            "Non-whitelisted strategy should return false"
        );
    }
}

// ============ Mock Slash Coordinator ============

contract MockSlashCoordinator is ISlashCoordinator {
    mapping(uint256 => SlashCoordinationStatus) private _statuses;
    mapping(uint256 => address) private _coverageProviders;

    function initiateSlash(address coverageProvider, uint256 claimId, uint256 amount)
        external
        returns (SlashCoordinationStatus)
    {
        _statuses[claimId] = SlashCoordinationStatus.Pending;
        _coverageProviders[claimId] = coverageProvider;
        emit SlashRequested(coverageProvider, claimId, amount);
        return SlashCoordinationStatus.Pending;
    }

    function status(address, uint256 claimId) external view returns (SlashCoordinationStatus) {
        return _statuses[claimId];
    }

    function setStatus(uint256 claimId, SlashCoordinationStatus _status) external {
        _statuses[claimId] = _status;
        address coverageProvider = _coverageProviders[claimId];
        if (_status == SlashCoordinationStatus.Passed) {
            emit SlashCompleted(coverageProvider, claimId, 0);
        } else if (_status == SlashCoordinationStatus.Failed) {
            emit SlashFailed(coverageProvider, claimId);
        }
    }
}

/// @notice Mock slash coordinator that immediately returns Passed status
contract MockSlashCoordinatorImmediate is ISlashCoordinator {
    mapping(uint256 => SlashCoordinationStatus) private _statuses;

    function initiateSlash(address coverageProvider, uint256 claimId, uint256 amount)
        external
        returns (SlashCoordinationStatus)
    {
        _statuses[claimId] = SlashCoordinationStatus.Passed;
        emit SlashRequested(coverageProvider, claimId, amount);
        emit SlashCompleted(coverageProvider, claimId, amount);
        return SlashCoordinationStatus.Passed;
    }

    function status(address, uint256 claimId) external view returns (SlashCoordinationStatus) {
        return _statuses[claimId];
    }
}

// ============ Mock Strategy ============

/// @notice Mock strategy for testing whitelist behavior with same underlying asset
contract MockStrategy {
    IERC20 private _underlyingToken;

    constructor(address underlyingToken_) {
        _underlyingToken = IERC20(underlyingToken_);
    }

    function underlyingToken() external view returns (IERC20) {
        return _underlyingToken;
    }
}
