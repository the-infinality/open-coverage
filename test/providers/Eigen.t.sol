// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EigenTestDeployer} from "../utils/EigenTestDeployer.sol";
import {CoveragePosition, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {
    CreatePositionAddtionalData,
    IEigenServiceManager
} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {EigenProviderMethods} from "utils/EigenProviderMethods.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";
import {CoverageProviderData} from "src/interfaces/ICoverageAgent.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";
import {CoverageClaim, CoverageClaimStatus} from "src/interfaces/ICoverageProvider.sol";
import {UniswapV3SwapperEngine} from "src/swapper-engines/UniswapV3SwapperEngine.sol";
import {UniswapAddressbook} from "utils/UniswapHelper.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {PriceStrategy, AssetPair} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {ISlashCoordinator, SlashStatus} from "src/interfaces/ISlashCoordinator.sol";
import {console2} from "forge-std/console2.sol";

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
            EigenProviderMethods.createOperatorProxy(
                eigenOperatorInstance, eigenServiceManager.eigenAddresses(), address(this), ""
            )
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

        // SwapParams memory swapParams = SwapParams({swapEngine: SwapEngine.UNISWAP_V3, poolInfo: poolInfo});
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

    function test_checkCoverageProviderRegistered() public view {
        CoverageProviderData memory coverageProviderData =
            coverageAgent.coverageProviderData(address(eigenCoverageDiamond));
        assertEq(coverageProviderData.active, true);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);
        eigenCoverageProvider.closePosition(positionId);
        assertEq(eigenCoverageProvider.position(positionId).expiryTimestamp, block.timestamp);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, 10e6);
        assertEq(claim.positionId, positionId);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

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
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, claimAmount, 30 days, reward);
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
    }

    function test_getAllocationedStrategies() public {
        // Setup with allocations
        _setupwithAllocations();

        address[] memory strategies =
            eigenServiceManager.getAllocationedStrategies(address(operator), address(coverageAgent));
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(_getTestStrategy()));
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

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
        eigenCoverageProvider.claimCoverage(positionId, claimAmount, 30 days, 10e6);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

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
        eigenCoverageProvider.claimCoverage(positionId, claimAmount, 30 days, 10e6);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        vm.expectRevert(ICoverageProvider.InvalidAmount.selector);
        eigenCoverageProvider.claimCoverage(positionId, 0, 30 days, 10e6);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );

        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, staker, address(coverageAgent))
        );
        eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);
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
            slashCoordinator: address(0)
        });

        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.DurationExceedsMax.selector, 30 days, 365 days));
        eigenCoverageProvider.claimCoverage(positionId, 1000e6, 365 days, 10e6);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        uint256 amount = 1000e6;
        uint256 duration = 30 days;
        uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InsufficientReward.selector, minimumReward, 10));
        eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10);
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
        vm.stopPrank();

        console2.log("block timestamp", block.timestamp);

        uint256 amount;
        uint32 duration;
        uint32 distributionStartTime;

        (amount, duration,) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);

        vm.warp(block.timestamp + 40 days);
        (amount, duration, distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 10e6);
        assertEq(duration, 30 days);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp - 40 days));
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
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
            slashCoordinator: slashCoordinator
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);
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
        claimId = eigenCoverageProvider.claimCoverage(positionId, claimAmount, duration, reward);

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

        // Get asset addresses
        address coverageAsset = coverageAgent.asset();
        address positionAsset = eigenCoverageProvider.position(positionId).asset;

        // Check balances before slashing
        uint256 contractCoverageBalanceBefore = IERC20(coverageAsset).balanceOf(address(eigenCoverageDiamond));
        uint256 coverageAgentBalanceBefore = IERC20(coverageAsset).balanceOf(address(coverageAgent));
        uint256 contractPositionBalanceBefore = IERC20(positionAsset).balanceOf(address(eigenCoverageDiamond));

        uint256 slashAmount = 10e6;
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        _executeSlash(claimIds, amounts);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)) - coverageAgentBalanceBefore,
            slashAmount,
            "Coverage agent should receive exact slashed amount"
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

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 500e6);
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
        uint256 claimId1 = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
        uint256 claimId2 = eigenCoverageProvider.claimCoverage(positionId, 500e6, 30 days, 5e6);
        vm.stopPrank();

        uint256[] memory claimIds = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        claimIds[0] = claimId1;
        claimIds[1] = claimId2;
        amounts[0] = 1000e6;
        amounts[1] = 500e6;

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
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);
    }

    /// @notice Test that slashing transfers tokens to coverage agent
    function test_slashClaims_tokenTransfer() public {
        uint256 positionId = _setupSlashingPosition(1000e18);
        uint256 initialBalance = IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent));
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        _executeSlash(claimIds, amounts);

        uint256 finalBalance = IERC20(coverageAgent.asset()).balanceOf(address(coverageAgent));
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
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);

        // Slash immediately after creation (should succeed)
        uint256[] memory claimIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        claimIds[0] = claimId;
        amounts[0] = 1000e6;

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
                ICoverageProvider.TimestampInvalid.selector, eigenCoverageProvider.claim(claimId).createdAt + 30 days
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

        vm.startPrank(address(coverageAgent));
        eigenCoverageProvider.completeClaims(claimId);
        vm.stopPrank();

        // Try to slash a completed claim
        vm.warp(block.timestamp - 1 days); // Go back to within duration window
        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);

        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId));
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

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, slashAmount);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.Slashed));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), slashAmount);
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));

        // Verify coverage agent receives exactly the slashed amount
        assertEq(
            IERC20(coverageAsset).balanceOf(address(coverageAgent)) - coverageAgentBalanceBefore,
            slashAmount,
            "Coverage agent should receive exact slashed amount"
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
            claimIds[i] = eigenCoverageProvider.claimCoverage(positionId, claimAmount, 30 days, reward);
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

        (uint256[] memory claimIds, uint256[] memory amounts) = _prepareSingleSlash(claimId, 1000e6);
        CoverageClaimStatus[] memory statuses = _executeSlash(claimIds, amounts, 15 days);

        assertEq(uint8(statuses[0]), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.PendingSlash));
        assertEq(eigenCoverageDiamond.claimSlashAmounts(claimId), 1000e6);

        // Complete the slash through coordinator
        coordinator.setStatus(claimId, SlashStatus.Completed);
        eigenCoverageProvider.completeSlash(claimId);

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }

    /// @notice Test completeSlash with invalid status should revert
    function test_RevertWhen_completeSlash_invalidStatus() public {
        MockSlashCoordinator coordinator = new MockSlashCoordinator();
        uint256 positionId = _setupSlashingPosition(1000e18, address(coordinator), Refundable.None);
        uint256 claimId = _createAndApproveClaim(positionId, 1000e6, 10e6);

        // Try to complete slash without initiating it first
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId));
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
        assertEq(uint8(coordinator.status(claimId)), uint8(SlashStatus.Pending));

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
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.InvalidClaim.selector, claimId));
        _executeSlash(claimIds, amounts);
    }
}

// ============ Mock Slash Coordinator ============

contract MockSlashCoordinator is ISlashCoordinator {
    mapping(uint256 => SlashStatus) private _statuses;

    function initiateSlash(uint256 claimId, uint256) external returns (SlashStatus) {
        _statuses[claimId] = SlashStatus.Pending;
        emit SlashRequested(claimId, 0);
        return SlashStatus.Pending;
    }

    function status(uint256 claimId) external view returns (SlashStatus) {
        return _statuses[claimId];
    }

    function setStatus(uint256 claimId, SlashStatus _status) external {
        _statuses[claimId] = _status;
        if (_status == SlashStatus.Completed) {
            emit SlashCompleted(claimId, 0);
        } else if (_status == SlashStatus.Failed) {
            emit SlashFailed(claimId);
        }
    }
}
