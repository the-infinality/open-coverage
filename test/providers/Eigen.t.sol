// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {EigenTestDeployer} from "../utils/EigenTestDeployer.sol";
import {CoveragePosition, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {CreatePositionAddtionalData} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
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
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {UniswapV4PoolInfo, SwapParams, SwapEngine} from "src/mixins/AssetPriceOracleAndSwapper.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";

import {CoverageClaim, CoverageClaimStatus} from "src/interfaces/ICoverageProvider.sol";

contract EigenTest is EigenTestDeployer {
    IEigenOperatorProxy public operator;
    MockPriceOracle public mockPriceOracle;
    address public staker;

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageProvider), address(coverageAgent), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator.allocate(address(eigenCoverageProvider), address(coverageAgent), strategyAddresses, magnitudes);
    }

    function _stakeAndDelegateToOperator(uint256 stakeAmount) internal {
                vm.startPrank(staker);
        IStrategyManager strategyManager = _getStrategyManager();
        
        // Approve strategy to spend tokens
        _getTestStrategy().underlyingToken().approve(address(strategyManager), stakeAmount);
        
        // Deposit into strategy
        strategyManager.depositIntoStrategy(_getTestStrategy(), _getTestStrategy().underlyingToken(), stakeAmount);

        // Delegate to operator (empty signature since no delegationApprover)
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySignature = ISignatureUtilsMixinTypes.SignatureWithExpiry({
            signature: "",
            expiry: 0
        });
        _getDelegationManager().delegateTo(address(operator), emptySignature, bytes32(0));

        vm.stopPrank();
    }

    function setUp() public override {
        super.setUp();

        staker = makeAddr("staker");

        deal(cbBTC, staker, 1000e18);

        operator = IEigenOperatorProxy(
            EigenProviderMethods.createOperatorProxy(
                eigenOperatorInstance, eigenCoverageProvider.eigenAddresses(), address(this), ""
            )
        );

        IPermissionController(eigenCoverageProvider.eigenAddresses().permissionController)
            .acceptAdmin(address(operator));

        coverageAgent.registerCoverageProvider(address(eigenCoverageProvider));
        eigenCoverageProvider.setStrategyWhitelist(address(_getTestStrategy()), true);

        mockPriceOracle = new MockPriceOracle(100000e18, cbBTC, USDC);

                // Add V4 pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbBTC),
            currency1: Currency.wrap(USDC),
            fee: 100,
            tickSpacing: 1,
            hooks: IHooks(address(0))
        });

        UniswapV4PoolInfo memory uniswapV4PoolInfo = UniswapV4PoolInfo({poolKey: poolKey, zeroForOne: true});

        SwapParams memory swapParams =
            SwapParams({swapEngine: SwapEngine.UNISWAP_V4_SINGLE_HOP, poolInfo: abi.encode(uniswapV4PoolInfo)});
        eigenCoverageProvider.registerPriceAdaptor(address(mockPriceOracle), cbBTC, USDC, swapParams);
    }

    function test_checkCoverageProviderRegistered() public view {
        CoverageProviderData memory coverageProviderData =
            coverageAgent.coverageProviderData(address(eigenCoverageProvider));
        assertEq(coverageProviderData.active, true);
    }

    function test_registerCoverageAgent() public {
        operator.registerCoverageAgent(address(eigenCoverageProvider), address(coverageAgent), 10000);
    }

    function test_allocate() public {
        _setupwithAllocations();
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageProvider), id: eigenCoverageProvider.getOperatorSetId(address(coverageAgent))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenCoverageProvider.eigenAddresses().allocationManager
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

    function test_mockPriceOracleQuotes() public view {
        uint256 quote = mockPriceOracle.getQuote(1e18, cbBTC, USDC);
        assertEq(quote, 100000e18);

        (uint256 bidOutAmount, uint256 askOutAmount) = mockPriceOracle.getQuotes(1e18, cbBTC, USDC);
        assertEq(bidOutAmount, 100000e18);
        assertEq(askOutAmount, 100000e18);

        quote = mockPriceOracle.getQuote(100000e18, USDC, cbBTC);
        assertEq(quote, 1e18);

        (bidOutAmount, askOutAmount) = mockPriceOracle.getQuotes(100000e18, USDC, cbBTC);
        assertEq(bidOutAmount, 1e18);
        assertEq(askOutAmount, 1e18);
    }

    function test_claimPosition() public {
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

        vm.prank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
        assertEq(claimId, 0);

        CoverageClaim memory claim = eigenCoverageProvider.claim(claimId);
        assertEq(claim.amount, 1000e6);
        assertEq(claim.duration, 30 days);
        assertEq(uint8(claim.status), uint8(CoverageClaimStatus.Issued));
        assertEq(claim.reward, 10e6);
        assertEq(claim.positionId, positionId);
    }

    function test_RevertWhen_claimPosition_insufficientCoverageOnClaim() public {
        _setupwithAllocations();

        _stakeAndDelegateToOperator(1e15);

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

        uint256 coverageAllocated = eigenCoverageProvider.coverageAllocated(address(operator), address(_getTestStrategy()), address(coverageAgent));

        vm.expectRevert(abi.encodeWithSelector(
            ICoverageProvider.InsufficientCoverageAvailable.selector,
            1000e6 - coverageAllocated
        ));
        vm.prank(address(coverageAgent));
        eigenCoverageProvider.claimCoverage(positionId, 1000e6, 30 days, 10e6);
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
        vm.expectRevert(abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, staker, address(coverageAgent)));
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
        assertApproxEqAbs(eigenCoverageProvider.positionMaxAmount(positionId), 1000e6, 4e5);
    }
}
