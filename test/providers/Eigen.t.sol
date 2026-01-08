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

        address[] memory strategies = eigenServiceManager.getAllocationedStrategies(address(operator), address(coverageAgent));
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
            abi.encodeWithSelector(ICoverageProvider.InsufficientCoverageAvailable.selector, claimAmount - coverageAllocated)
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
            abi.encodeWithSelector(ICoverageProvider.InsufficientCoverageAvailable.selector, claimAmount - coverageAllocated)
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

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);
        assertEq(distributionStartTime, toRewardsInterval(block.timestamp));

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

        (uint256 amount, uint32 duration, uint32 distributionStartTime) = eigenServiceManager.captureRewards(claimId);
        assertEq(amount, 0);
        assertEq(duration, 0);
        assertEq(distributionStartTime, block.timestamp / CALCULATION_INTERVAL_SECONDS * CALCULATION_INTERVAL_SECONDS);

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

    function xtest_slashClaims() public {
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

        uint256[] memory claimIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.startPrank(address(coverageAgent));
        IERC20(coverageAgent.asset()).approve(address(eigenCoverageDiamond), 10e6);
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);

        claimIds[0] = claimId;
        amounts[0] = 10e6;
        eigenCoverageProvider.slashClaims(claimIds, amounts);
        vm.stopPrank();

        assertEq(uint8(eigenCoverageProvider.claim(claimId).status), uint8(CoverageClaimStatus.Slashed));
    }
}
