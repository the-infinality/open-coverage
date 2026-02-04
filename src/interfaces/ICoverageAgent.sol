// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct ClaimCoverageRequest {
    /// @notice Address of the coverage provider to claim coverage from.
    address coverageProvider;
    /// @notice The coverage position to claim coverage from.
    uint256 positionId;
    /// @notice The amount of coverage to claim in the units of the agent's asset.
    uint256 amount;
    /// @notice The reward for the coverage provider
    uint256 reward;
    /// @notice The duration of the coverage to claim.
    uint256 duration;
}

struct Claim {
    /// @notice The coverage provider that issued the claim.
    address coverageProvider;
    /// @notice The id of the claim.
    uint256 claimId;
}

struct Coverage {
    Claim[] claims;
    bool reservation;
}

/// @title ICoverageAgent
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage agent.
interface ICoverageAgent {
    event CoverageProviderRegistered(address indexed coverageProvider);
    event CoverageClaimed(uint256 indexed coverageId);
    event CoverageReserved(uint256 indexed coverageId);
    event CoverageSlashed(uint256 indexed coverageId);
    event CoverageRepaid(uint256 indexed coverageId);
    event MetadataUpdated(string metadataUri);

    error InvalidCoverage(uint256 coverageId);
    error CoverageProviderNotRegistered();
    error CoverageNotReservation(uint256 coverageId);
    error CoverageAlreadyConverted(uint256 coverageId);

    /// ============ Coverage Providers ============

    /// @notice Register a coverage provider.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @param coverageProvider The coverage provider to register.
    function registerCoverageProvider(address coverageProvider) external;

    /// @notice Triggered when a coverage position has been registered with a coverage provider.
    /// @dev A coverage position is a guarantee from the coverage provider to provide coverage within their given parameters.
    /// @param positionId The coverage position to register.
    function onRegisterPosition(uint256 positionId) external;

    /// @notice Triggered when a coverage claim has been slashed.
    /// @dev Can only be called by the coverage provider that issued the claim.
    /// @param claimId The claim id slashed.
    /// @param slashAmount The amount that was slashed.
    function onSlashCompleted(uint256 claimId, uint256 slashAmount) external;

    /// @notice Triggered when a coverage claim has been refunded if it was closed early.
    /// @dev Can only be called by the coverage provider that issued the claim.
    /// @param claimId The claim id refunded.
    /// @param refundAmount The amount that was refunded.
    function onClaimRefunded(uint256 claimId, uint256 refundAmount) external;

    /// ============ Discovery ============

    /// @notice Get the coverage providers registered with the coverage agent.
    /// @return coverageProviderAddresses The coverage providers.
    function registeredCoverageProviders() external view returns (address[] memory coverageProviderAddresses);

    /// @notice Check if a coverage provider is registered with the coverage agent.
    /// @param coverageProvider The coverage provider to check.
    /// @return isRegistered Whether the coverage provider is registered.
    function isCoverageProviderRegistered(address coverageProvider) external view returns (bool isRegistered);

    /// @notice Get the coverage for a given coverage id.
    /// @param coverageId The coverage id to get the coverage for.
    /// @return coverage The coverage data
    function coverage(uint256 coverageId) external view returns (Coverage memory coverage);

    /// @notice Get the asset that the coverage agent requires coverage on
    /// @dev The asset must be an ERC20 token. Rewards will be paid in this asset.
    /// @return asset The asset address.
    function asset() external view returns (address);

    /// @notice Get the coordinator that manages the coverage agent
    /// @dev The coordinator must be represented by an address and could be a contract or an account.
    /// @return coordinator The coordinator address.
    function coordinator() external view returns (address);
}
