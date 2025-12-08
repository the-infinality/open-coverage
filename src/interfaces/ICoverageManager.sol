// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct CoveragePosition {
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

    /// @notice Whether the coverage position is refundable if the coverage pool can not meet its obligations.
    /// @dev If true, the coverage manager must provide contingencies to fully refund the premium to allow the coverage pool to 
    /// purchase coverage for the remaining duration of the coverage position.
    bool refundable;

    /// @notice The address of the slash coordinator for the coverage position.
    /// @dev The slash coordinator is responsible for initiating the slashing process for the coverage position.
    /// If no slash coordinator is set, the coverage manager will instantly slash the coverage position.
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
}

/// @title ICoverageManager
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage manager that can slash a delegator and distribute rewards.
interface ICoverageManager {
    event PositionCreated(uint256 indexed positionId);
    event PositionUpdated(uint256 indexed positionId);
    event ClaimIssued(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration);
    event Slashed(uint256 indexed claimId, uint256 amount);
    event Liquidated(uint256 indexed claimId);
    event ClaimCompleted(uint256 indexed claimId);

    error PositionExpired(uint256 positionId);
    error TimestampInvalid(uint256 timestamp);
    error MinRateInvalid(uint16 minRate);


    /// ============ Hooks ============

    /// @notice Triggered when a coverage pool is registered by the coverage pool.
    /// @dev Can only be called by the coverage pool. This hook should always be called by
    /// the coverage pool and can be used for activities such as whitelisting the coverage pool.
    function onIsRegistered() external;


    /// ============ Coverage Positions ============

    /// @notice Create a new coverage position and register it with a coverage pool.
    /// @dev Should call the `registerPosition` function of the coverage pool.
    /// @param coveragePool The coverage pool to create the coverage position for.
    /// @param data The coverage position data to create.
    /// @param additionalData Any extra data to be used when creating the position
    /// @return positionId The id of the created coverage position.
    function createPosition(address coveragePool, CoveragePosition memory data, bytes calldata additionalData) external returns (uint256 positionId);

    /// @notice Update a coverage position.
    /// @dev This can be called without notifying the coverage pool because it is assumed that they are already aware via events emitted.
    /// @param positionId The id of the coverage position to update.
    /// @param data The coverage position data to update.
    function updatePosition(uint256 positionId, CoveragePosition memory data) external;


    /// ============ Coverage Claims ============

    /// @notice Issue coverage for a coverage position.
    /// @dev The purchaser of the coverage should approve the coverage manager to claim the coverage premium.
    /// @param positionId ID of the coverage position to claim coverage from.
    /// @param amount The amount of coverage to claim.
    /// @param duration The duration of the coverage to claim.
    /// @param paymentAsset The asset to pay the coverage premium in.
    /// @param paymentAmount The amount of the coverage premium to pay in the payment asset.
    /// @return claimId ID of the coverage claim on success.
    function issueCoverage(uint256 positionId, uint256 amount, uint256 duration, address paymentAsset, uint256 paymentAmount) external returns (uint256 claimId);

    /// @notice Liquidate a coverage claim if it doesn't meet its obligations.
    /// @dev This should be called by the coverage pool if the coverage position doesn't meet its obligations.
    /// @param claimId The id of the coverage position to liquidate.
    function liquidateClaim(uint256 claimId) external;

    /// @notice Complete a coverage claim.
    /// @dev This can be called by anyone if the coverage claim is completed and should be removed from coverage tracking.
    /// If a claim is in the pending slash state, it can only be completed as a result of the slashing process.
    /// @param claimId The id of the coverage claim to complete.
    function completeClaims(uint256 claimId) external;

    /// @notice Slash on coverage claims.
    /// @dev Can only be called by a coverage pool. Should take a slash coordinator into account if set.
    /// @param claimIds The ids of the coverage claims to slash.
    /// @param amounts The amounts of the slashes.
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts) external;


    /// ============ Discovery ============

    /// @notice Get the amount of the delegation for a given coverage pool.
    /// @param coveragePool The target of the delegation.
    /// @return amount Total coverage issued to a pool.
    function totalCoverageByPool(address coveragePool) external view returns (uint256 amount);

    /// @notice Get the coverage position for a given coverage id.
    /// @param positionId The position id to get the position for.
    /// @return position The coverage position.
    function position(uint256 positionId) external view returns (CoveragePosition memory position);

    /// @notice Get the coverage claim for a given claim id.
    /// @param claimId The claim id
    /// @return claim The coverage claim.
    function claim(uint256 claimId) external view returns (CoverageClaim memory claim);
}
