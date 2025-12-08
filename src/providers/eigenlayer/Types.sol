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
}

struct OperatorData {
    uint32 createdAtEpoch;
}

struct DelegatorData {
    uint256 minRate;
}
