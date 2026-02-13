// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20v5} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {IERC173} from "src/diamond/interfaces/IERC173.sol";
import {EigenTestDeployer} from "../../utils/EigenTestDeployer.sol";
import {CoveragePosition, Refundable} from "src/interfaces/ICoverageProvider.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {PriceStrategy, AssetPair} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";

contract EigenPermissionsTest is EigenTestDeployer {
    // ============ Diamond ownership ============

    function test_owner() public view {
        assertEq(IERC173(address(eigenCoverageDiamond)).owner(), address(this));
    }

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(address(this));
        IERC173(address(eigenCoverageDiamond)).transferOwnership(newOwner);
        assertEq(IERC173(address(eigenCoverageDiamond)).owner(), newOwner);
    }

    // ============ Owner-only guards ============

    function test_RevertWhen_register_not_owner() public {
        address nonOwner = makeAddr("nonOwner");
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        vm.prank(nonOwner);
        vm.expectRevert("LibDiamond: Must be contract owner");
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

    function test_RevertWhen_setSwapSlippage_not_owner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("LibDiamond: Must be contract owner");
        eigenPriceOracle.setSwapSlippage(50);
    }

    function test_RevertWhen_updateAVSMetadataURI_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        string memory newMetadataURI = "https://new-coverage.example.com/metadata.json";

        vm.prank(nonOwner);
        vm.expectRevert("LibDiamond: Must be contract owner");
        eigenServiceManager.updateAVSMetadataURI(newMetadataURI);
    }

    function test_RevertWhen_setStrategyWhitelist_notOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert("LibDiamond: Must be contract owner");
        eigenServiceManager.setStrategyWhitelist(address(_getTestStrategy()), false);
    }

    // ============ Operator authorization guards ============

    function test_RevertWhen_createPosition_notAuthorized() public {
        _setupwithAllocations();

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

    function test_RevertWhen_setCoverageThreshold_notAuthorized() public {
        _setupwithAllocations();

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IEigenServiceManager.NotOperatorAuthorized.selector, address(operator), unauthorized)
        );
        eigenCoverageLiquidatable.setCoverageThreshold(bytes32(uint256(uint160(address(operator)))), 9000);
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

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(IEigenServiceManager.NotOperatorAuthorized.selector, address(operator), unauthorized)
        );
        eigenCoverageProvider.closePosition(positionId);
    }

    // ============ Coverage agent-only guards ============

    function test_RevertWhen_issueClaim_notCoverageAgent() public {
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
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, staker, address(coverageAgent))
        );
        eigenCoverageProvider.issueClaim(positionId, 1000e6, 30 days, 10e6);
    }

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

    function test_RevertWhen_reserveClaim_notCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, unauthorized, address(coverageAgent))
        );
        eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);
    }

    function test_RevertWhen_convertReservedClaim_notCoverageAgent() public {
        uint256 positionId = _setupPositionWithReservation(10e18, 1 hours);

        vm.prank(address(coverageAgent));
        uint256 claimId = eigenCoverageProvider.reserveClaim(positionId, 1000e6, 30 days, 10e6);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(ICoverageProvider.NotCoverageAgent.selector, unauthorized, address(coverageAgent))
        );
        eigenCoverageProvider.convertReservedClaim(claimId, 1000e6, 30 days, 10e6);
    }

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

    // ============ Internal-only guards ============

    function test_RevertWhen_submitOperatorReward_notInternal() public {
        IStrategy strategy = _getTestStrategy();
        address asset = coverageAgent.asset();

        vm.expectRevert("Only internal calls");
        eigenServiceManager.submitOperatorReward(
            address(operator), strategy, IERC20v5(asset), 1e6, 0, 1 days, "Test reward"
        );
    }

    function test_RevertWhen_slashOperator_notInternal() public {
        address strategy = address(_getTestStrategy());

        vm.expectRevert("Only internal calls");
        eigenServiceManager.slashOperator(address(operator), strategy, address(coverageAgent), 100e6);
    }

    // ============ AVS validation ============

    function test_RevertWhen_registerOperator_invalidAVS() public {
        address randomAVS = makeAddr("randomAVS");
        uint32[] memory operatorSetIds = new uint32[](0);

        vm.expectRevert(abi.encodeWithSelector(IEigenServiceManager.InvalidAVS.selector, randomAVS));
        eigenServiceManager.registerOperator(address(this), randomAVS, operatorSetIds, "");
    }

    function test_RevertWhen_registerOperator_calledByDelegationManager() public {
        address delegationManager = eigenServiceManager.eigenAddresses().delegationManager;
        uint32[] memory operatorSetIds = new uint32[](0);

        vm.prank(delegationManager);
        vm.expectRevert("Not delegation manager");
        eigenServiceManager.registerOperator(address(this), address(eigenCoverageDiamond), operatorSetIds, "");
    }
}
