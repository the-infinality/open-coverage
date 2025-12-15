// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Refund policy for coverage positions on liquidation
/// @dev None - No reward refund
/// @dev TimeWeighted - Refund reward based on time position has been open
/// @dev Full - Full refund of reward on liquidation
enum Refundable {
    None,
    TimeWeighted,
    Full
}

struct CoveragePosition {
    /// @notice The address of the coverage agent that this position will cover.
    address coverageAgent;

    /// @notice The minimum rate for any delegation locking.
    /// @dev Rate is in basis points per annum
    uint16 minRate;

    /// @notice The maximum duration of any delegation locking in seconds.
    /// @dev If 0 there is no maximum duration.
    uint256 maxDuration;

    /// @notice The timestamp at which the coverage position expires.
    /// @dev If 0 there is no expiry block.
    uint256 expiryTimestamp;

    /// @notice The asset that the coverage position is denominated in.
    address asset;

    /// @notice The refund policy if the coverage agent cannot meet its obligations.
    /// @dev The coverage provider must provide contingencies based on the refund policy:
    /// - None: No refund required
    /// - TimeWeighted: Refund proportional to remaining duration (e.g., 50% refund if 6 months remain of 12 month position)
    /// - Full: Complete refund of reward to allow coverage agent to purchase coverage for remaining duration
    Refundable refundable;

    /// @notice The address of the slash coordinator for the coverage position.
    /// @dev The slash coordinator is responsible for initiating the slashing process for the coverage position.
    /// If no slash coordinator is set, the coverage provider will instantly slash the coverage position.
    address slashCoordinator;
}

enum CoverageClaimStatus {
    Issued,
    Liquidated,
    Completed,
    PendingSlash,
    Slashed
}

struct CoverageClaim {
    uint256 positionId;
    uint256 amount;
    uint256 duration;
    CoverageClaimStatus status;
    uint256 reward;
}

/// @title ICoverageProvider
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage provider that can slash a delegator and distribute rewards.
interface ICoverageProvider {
    event PositionCreated(uint256 indexed positionId);
    event PositionClosed(uint256 indexed positionId);
    event CoverageIssued(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration);
    event ClaimIssued(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration);
    event Slashed(uint256 indexed claimId, uint256 amount);
    event Liquidated(uint256 indexed claimId);
    event ClaimCompleted(uint256 indexed claimId);

    error PositionExpired(uint256 positionId);
    error TimestampInvalid(uint256 timestamp);
    error MinRateInvalid(uint16 minRate);
    error NotCoverageAgent(address caller, address required);
    error InsufficientReward(uint256 minimumReward, uint256 reward);
    error InsufficientCoverageAvailable(uint256 deficit);

    /// ============ Hooks ============

    /// @notice Triggered when a coverage agent is registered by the coverage agent.
    /// @dev Can only be called by the coverage agent. This hook should always be called by
    /// the coverage agent and can be used for activities such as whitelisting the coverage agent.
    function onIsRegistered() external;

    /// ============ Coverage Positions ============

    /// @notice Create a new coverage position and register it with a coverage agent.
    /// @dev Should call the `registerPosition` function of the coverage agent.
    /// @param coverageAgent The coverage agent to create the coverage position for.
    /// @param data The coverage position data to create.
    /// @param additionalData Any extra data to be used when creating the position
    /// @return positionId The id of the created coverage position.
    function createPosition(address coverageAgent, CoveragePosition memory data, bytes calldata additionalData)
        external
        returns (uint256 positionId);

    /// @notice Close a coverage position.
    /// @param positionId The id of the coverage position to close.
    function closePosition(uint256 positionId) external;

    /// ============ Coverage Claims ============

    /// @notice Claim coverage for a coverage position.
    /// @dev The purchaser of the coverage should approve the coverage provider to claim the coverage reward.
    /// @param positionId ID of the coverage position to claim coverage from.
    /// @param amount The amount of coverage to claim.
    /// @param duration The duration of the coverage to claim.
    /// @param reward The amount of the coverage reward to pay.
    /// @return claimId ID of the coverage claim on success.
    function claimCoverage(
        uint256 positionId,
        uint256 amount,
        uint256 duration,
        uint256 reward
    ) external returns (uint256 claimId);

    /// @notice Liquidate a coverage claim if it doesn't meet its obligations.
    /// @dev This should be called by the coverage agent if the coverage position doesn't meet its obligations.
    /// @param claimId The id of the coverage position to liquidate.
    function liquidateClaim(uint256 claimId) external;

    /// @notice Complete a coverage claim.
    /// @dev This can be called by anyone if the coverage claim is completed and should be removed from coverage tracking.
    /// If a claim is in the pending slash state, it can only be completed as a result of the slashing process.
    /// @param claimId The id of the coverage claim to complete.
    function completeClaims(uint256 claimId) external;

    /// @notice Slash on coverage claims.
    /// @dev Can only be called by a coverage agent. Should take a slash coordinator into account if set.
    /// @param claimIds The ids of the coverage claims to slash.
    /// @param amounts The amounts of the slashes.
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses);

    /// ============ Discovery ============

    /// @notice Get the coverage position for a given coverage id.
    /// @param positionId The position id to get the position for.
    /// @return position The coverage position.
    function position(uint256 positionId) external view returns (CoveragePosition memory position);

    /// @notice Get the maximum amount of coverage available for a given position.
    /// @param positionId The position id to get the maximum amount for.
    /// @return maxAmount The maximum amount of coverage for the position.
    function positionMaxAmount(uint256 positionId) external view returns (uint256 maxAmount);

    /// @notice Get the coverage claim for a given claim id.
    /// @param claimId The claim id
    /// @return claim The coverage claim.
    function claim(uint256 claimId) external view returns (CoverageClaim memory claim);

    /// @notice Check if a claim is covered.
    /// @dev If the deficit is anything above 0 the claim should be considered for liquidation.
    /// @param claimId The claim id to check if it is covered.
    /// @return deficit The deficit of coverage for the claim.
    function claimDeficit(uint256 claimId) external view returns (uint256 deficit);
}
