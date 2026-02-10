// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum SlashCoordinationStatus {
    Pending,
    Passed,
    Failed
}

/// @title ISlashCoordinator
/// @author p-dealwis, Infinality
/// @notice An interface for a slash coordinator that can slash a coverage claim.
interface ISlashCoordinator {
    event SlashRequested(address indexed coverageProvider, uint256 indexed claimId, uint256 amount);
    event SlashCompleted(address indexed coverageProvider, uint256 indexed claimId, uint256 amount);
    event SlashFailed(address indexed coverageProvider, uint256 indexed claimId);

    /// @notice Initiate the slashing process for a coverage claim.
    /// @dev Can only be called by the coverage provider issuing the claim.
    /// @param coverageProvider The coverage provider issuing the slash.
    /// @param claimId The id of the coverage claim to slash.
    function initiateSlash(address coverageProvider, uint256 claimId, uint256 amount)
        external
        returns (SlashCoordinationStatus status);

    /// ============ Discovery ============

    /// @notice Get the status of the slashing process for a coverage claim.
    /// @param coverageProvider The coverage provider that initiated the slash.
    /// @param claimId The id of the coverage claim to get the status for.
    /// @return status The status of the slashing process.
    function status(address coverageProvider, uint256 claimId) external view returns (SlashCoordinationStatus status);
}
