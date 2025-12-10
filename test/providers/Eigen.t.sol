// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

contract EigenTest is EigenTestDeployer {
    IEigenOperatorProxy public operator;

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operator.registerCoverageAgent(address(eigenCoverageProvider), address(coverageAgent), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator.allocate(address(eigenCoverageProvider), address(coverageAgent), strategyAddresses, magnitudes);
    }

    function setUp() public override {
        super.setUp();

        operator = IEigenOperatorProxy(
            EigenProviderMethods.createOperatorProxy(
                eigenOperatorInstance, eigenCoverageProvider.eigenAddresses(), address(this), ""
            )
        );

        IPermissionController(eigenCoverageProvider.eigenAddresses().permissionController)
            .acceptAdmin(address(operator));

        coverageAgent.registerCoverageProvider(address(eigenCoverageProvider));
        eigenCoverageProvider.setStrategyWhitelist(address(_getTestStrategy()), true);
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

    // ============ Reward Distribution Tests ============

    function test_rewardDistribution_None_ImmediateDistribution() public {
        _setupwithAllocations();

        // Create position with Refundable.None
        CoveragePosition memory data = CoveragePosition({
            minRate: 100, // 1% per annum
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        // Issue coverage
        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days); // 10 ether

        uint256 claimId = eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Check that rewards were distributed immediately
        uint256 pendingRewards = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewards, premium, "Rewards should be immediately pending for Refundable.None");
    }

    function test_rewardDistribution_TimeWeighted_OnLiquidation() public {
        _setupwithAllocations();

        // Create position with Refundable.TimeWeighted
        CoveragePosition memory data = CoveragePosition({
            minRate: 100, // 1% per annum
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        // Issue coverage
        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days); // 10 ether

        uint256 claimId = eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Initially no rewards should be pending
        uint256 pendingRewardsBefore = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsBefore, 0, "No rewards should be pending initially for TimeWeighted");

        // Advance time by 50% of duration
        vm.warp(block.timestamp + (duration / 2));

        // Liquidate claim
        eigenCoverageProvider.liquidateClaim(claimId);

        // Check that 50% of rewards are now pending
        uint256 pendingRewardsAfter = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertApproxEqAbs(pendingRewardsAfter, premium / 2, 1e10, "Should have ~50% of rewards after liquidation at 50% time");
    }

    function test_rewardDistribution_TimeWeighted_OnCompletion() public {
        _setupwithAllocations();

        // Create position with Refundable.TimeWeighted
        CoveragePosition memory data = CoveragePosition({
            minRate: 100, // 1% per annum
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.TimeWeighted,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        // Issue coverage
        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days); // 10 ether

        uint256 claimId = eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Initially no rewards should be pending
        uint256 pendingRewardsBefore = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsBefore, 0, "No rewards should be pending initially for TimeWeighted");

        // Advance time past duration
        vm.warp(block.timestamp + duration + 1);

        // Complete claim
        eigenCoverageProvider.completeClaims(claimId);

        // Check that all rewards are now pending
        uint256 pendingRewardsAfter = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsAfter, premium, "Should have 100% of rewards after completion");
    }

    function test_rewardDistribution_Full_OnCompletion() public {
        _setupwithAllocations();

        // Create position with Refundable.Full
        CoveragePosition memory data = CoveragePosition({
            minRate: 100, // 1% per annum
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        // Issue coverage
        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days); // 10 ether

        uint256 claimId = eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Initially no rewards should be pending
        uint256 pendingRewardsBefore = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsBefore, 0, "No rewards should be pending initially for Full");

        // Advance time past duration
        vm.warp(block.timestamp + duration + 1);

        // Complete claim
        eigenCoverageProvider.completeClaims(claimId);

        // Check that all rewards are now pending
        uint256 pendingRewardsAfter = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsAfter, premium, "Should have 100% of rewards after completion");
    }

    function test_rewardDistribution_Full_NoRewardsOnLiquidation() public {
        _setupwithAllocations();

        // Create position with Refundable.Full
        CoveragePosition memory data = CoveragePosition({
            minRate: 100, // 1% per annum
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.Full,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        // Issue coverage
        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days); // 10 ether

        uint256 claimId = eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Advance time by 50% of duration
        vm.warp(block.timestamp + (duration / 2));

        // Liquidate claim
        eigenCoverageProvider.liquidateClaim(claimId);

        // Check that no rewards are pending (Full refund means no rewards on liquidation)
        uint256 pendingRewardsAfter = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsAfter, 0, "Should have no rewards after liquidation for Full refundable");
    }

    function test_claimRewards_Success() public {
        _setupwithAllocations();

        // Create position and issue coverage with Refundable.None (immediate distribution)
        CoveragePosition memory data = CoveragePosition({
            minRate: 100,
            maxDuration: 365 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageProvider.createPosition(address(coverageAgent), data, additionalData);

        uint256 coverageAmount = 1000 ether;
        uint256 duration = 365 days;
        uint256 premium = (coverageAmount * 100 * duration) / (10000 * 365 days);

        eigenCoverageProvider.issueCoverage(
            positionId,
            coverageAmount,
            duration,
            address(_getTestStrategy().underlyingToken()),
            premium
        );

        // Check pending rewards before claim
        uint256 pendingRewardsBefore = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsBefore, premium);

        // Claim rewards (as the operator proxy)
        vm.prank(address(operator));
        uint256 claimedAmount = eigenCoverageProvider.claimRewards(address(operator), address(coverageAgent));
        assertEq(claimedAmount, premium);

        // Check that pending rewards are now 0
        uint256 pendingRewardsAfter = eigenCoverageProvider.getPendingRewards(address(operator), address(coverageAgent));
        assertEq(pendingRewardsAfter, 0);

        // Check claimed rewards tracking
        uint256 totalClaimed = eigenCoverageProvider.getClaimedRewards(address(operator), address(coverageAgent));
        assertEq(totalClaimed, premium);
    }

    function test_claimRewards_NoRewardsReverts() public {
        _setupwithAllocations();

        // Try to claim rewards when there are none
        vm.prank(address(operator));
        vm.expectRevert(abi.encodeWithSignature("NoRewardsToClaim()"));
        eigenCoverageProvider.claimRewards(address(operator), address(coverageAgent));
    }
}
