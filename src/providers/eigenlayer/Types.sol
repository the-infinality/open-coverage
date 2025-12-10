// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Eigen addresses
/// @param allocationManager Allocation manager address
/// @param delegationManager Delegation manager address
/// @param strategyManager Strategy manager address
/// @param rewardsCoordinator Rewards coordinator address
struct EigenAddresses {
    /// @notice The address of the allocation manager.
    /// @dev Accessible via IAllocationManager interface.
    address allocationManager;
    address delegationManager;
    address strategyManager;
    address rewardsCoordinator;
    address permissionController;
}

struct OperatorData {
    uint32 createdAtEpoch;
}

struct DelegatorData {
    uint256 minRate;
}

/// @dev Reward information for a specific claim
/// @param totalReward Total reward amount allocated to this claim
/// @param distributedReward Amount of reward already distributed
/// @param startTime Timestamp when the claim started
/// @param endTime Timestamp when the claim ends
/// @param liquidationTime Timestamp when claim was liquidated (0 if not liquidated)
struct ClaimReward {
    uint256 totalReward;
    uint256 distributedReward;
    uint256 startTime;
    uint256 endTime;
    uint256 liquidationTime;
}

/// @dev Operator reward tracking per coverage agent
/// @param pendingRewards Rewards that can be claimed by the operator
/// @param claimedRewards Total rewards claimed by the operator
struct OperatorRewards {
    uint256 pendingRewards;
    uint256 claimedRewards;
}
