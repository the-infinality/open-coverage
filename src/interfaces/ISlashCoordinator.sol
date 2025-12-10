// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum SlashStatus {
    Pending,
    Completed,
    Failed
}

/// @title ISlashCoordinator
/// @author p-dealwis, Infinality
/// @notice An interface for a slash coordinator that can slash a coverage claim.
interface ISlashCoordinator {
    event SlashRequested(uint256 indexed claimId, uint256 amount);
    event SlashCompleted(uint256 indexed claimId, uint256 amount);
    event SlashFailed(uint256 indexed claimId);

    /// @notice Initiate the slashing process for a coverage claim.
    /// @dev Can only be called by the coverage provider issuing the claim.
    /// @param claimId The id of the coverage claim to slash.
    function initiateSlash(uint256 claimId) external returns (SlashStatus status);

    /// ============ Discovery ============

    /// @notice Get the status of the slashing process for a coverage claim.
    /// @param claimId The id of the coverage claim to get the status for.
    /// @return status The status of the slashing process.
    function status(uint256 claimId) external view returns (SlashStatus status);
}
