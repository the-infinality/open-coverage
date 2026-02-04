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

    /// @notice The asset used for coverage of the position.
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

    /// @notice The maximum amount of time in seconds that a reservation is valid for since it was created.
    /// @dev If 0 there is no maximum reservation time (reservations are not allowed).
    uint256 maxReservationTime;

    /// @notice The ID representing the operator that will cover the coverage position.
    /// @dev This is an optional field that should be used if a Coverage Provider has multiple operators.
    bytes32 operatorId;
}

enum CoverageClaimStatus {
    Issued,
    Completed,
    PendingSlash,
    Slashed,
    Reserved,
    Repaid
}

struct CoverageClaim {
    uint256 positionId;
    uint256 amount;
    uint256 duration;
    uint256 createdAt;
    CoverageClaimStatus status;
    uint256 reward;
}

/// @title ICoverageProvider
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage provider that can slash a delegator and distribute rewards.
interface ICoverageProvider {
    event PositionCreated(uint256 indexed positionId);
    event PositionClosed(uint256 indexed positionId);
    event ClaimIssued(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration);
    event ClaimReserved(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration);
    event ClaimClosed(uint256 indexed claimId);
    event ClaimLiquidated(uint256 indexed claimId);
    event ClaimSlashed(uint256 indexed claimId, uint256 amount);
    event ClaimSlashPending(uint256 indexed claimId, address slashCoordinator);
    event ClaimRepayment(uint256 indexed claimId, uint256 amount);
    event ClaimRepaid(uint256 indexed claimId);
    event MetadataUpdated(string metadataUri);

    error InvalidAmount();
    error PositionExpired(uint256 positionId);
    error TimestampInvalid(uint256 timestamp);
    error MinRateInvalid(uint16 minRate);
    error NotCoverageAgent(address caller, address required);
    error InsufficientReward(uint256 minimumReward, uint256 reward);
    error RewardTransferFailed();
    error InsufficientCoverageAvailable(uint256 deficit);
    error DurationExceedsMax(uint256 maxDuration, uint256 duration);
    error DurationExceedsExpiry(uint256 expiryTimestamp, uint256 completionTimestamp);
    error InvalidClaim(uint256 claimId);
    error SlashFailed(uint256 claimId);
    error SlashAmountExceedsClaim(uint256 claimId, uint256 slash, uint256 claim);
    error ReservationNotAllowed(uint256 positionId);
    error ReservationExpired(uint256 claimId);
    error AmountExceedsReserved(uint256 claimId, uint256 amount, uint256 reserved);
    error DurationExceedsReserved(uint256 claimId, uint256 duration, uint256 reserved);
    error ClaimNotReserved(uint256 claimId);
    error ClaimNotExpired(uint256 claimId);

    /// ============ Hooks ============

    /// @notice Triggered when a coverage agent registers.
    /// @dev Can only be called by the coverage agent.
    function onIsRegistered() external;

    /// ============ Coverage Positions ============

    /// @notice Create a new coverage position and register it with a coverage agent.
    /// @dev Should call the `registerPosition` function of the coverage agent.
    /// @param data The coverage position data to create (includes coverageAgent address).
    /// @param additionalData Any extra data to be used when creating the position
    /// @return positionId The id of the created coverage position.
    function createPosition(CoveragePosition memory data, bytes calldata additionalData)
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
    function issueClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId);

    /// @notice Reserve coverage for a coverage position.
    /// @dev Reserves coverage without immediately requiring the full reward payment.
    /// The reservation can be converted to an issued claim within the maxReservationTime.
    /// @param positionId ID of the coverage position to reserve coverage from.
    /// @param amount The amount of coverage to reserve.
    /// @param duration The duration of the coverage to reserve.
    /// @param reward The amount of the coverage reward that will be paid on conversion.
    /// @return claimId ID of the reserved coverage claim on success.
    function reserveClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward)
        external
        returns (uint256 claimId);

    /// @notice Convert a reserved claim to an issued claim.
    /// @dev Can only be called by the coverage agent that created the reservation.
    /// The amount and duration can be less than or equal to the reserved amounts.
    /// @param claimId The ID of the reserved claim to convert.
    /// @param amount The amount of coverage to claim (must be <= reserved amount).
    /// @param duration The duration of the coverage (must be <= reserved duration).
    /// @param reward The reward to pay (must be adequate pro-rata based on amount and duration).
    function convertReservedClaim(uint256 claimId, uint256 amount, uint256 duration, uint256 reward) external;

    /// @notice Close a coverage claim.
    /// @dev Can be called by anyone if the reservation has expired (createdAt + maxReservationTime < block.timestamp).
    /// @dev Can be called by anyone if an issued claim's duration has elapsed (createdAt + duration <= block.timestamp).
    /// @dev Can be called by the coverage agent that made the claim to close their own claim early.
    /// @param claimId The ID of the claim to close.
    function closeClaim(uint256 claimId) external;

    /// @notice Liquidate a coverage claim if it doesn't meet its obligations.
    /// @dev This should be called by the coverage agent if the coverage position doesn't meet its obligations.
    /// @param claimId The id of the coverage position to liquidate.
    function liquidateClaim(uint256 claimId) external;

    /// @notice Slash on coverage claims.
    /// @dev Can only be called by a coverage agent. Should take a slash coordinator into account if set.
    /// @param claimIds The ids of the coverage claims to slash.
    /// @param amounts The amounts of the slashes.
    function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts)
        external
        returns (CoverageClaimStatus[] memory slashStatuses);

    /// @notice Complete the slashing process for a coverage claim.
    /// @dev Can only be called by the slash coordinator that initiated the slashing process.
    /// @param claimId The id of the coverage claim to complete the slashing process for.
    function completeSlash(uint256 claimId) external;

    /// @notice Repay a claim that has been slashed
    /// @dev Can only be called by the coverage agent that issued the claim.
    /// @param claimId The id of the claim to repay.
    /// @param amount The amount of the coverage claim to repay.
    function repaySlashedClaim(uint256 claimId, uint256 amount) external;

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

    /// @notice Get the total available backing for a claim.
    /// @dev A negative value indicates a backing deficit, while a positive value means the claim is fully backed.
    /// @param claimId The claim id to check backing for.
    /// @return backing The total available backing for the claim (negative = deficit, positive = fully backed).
    function claimBacking(uint256 claimId) external view returns (int256 backing);

    /// @notice Get the total amount slashed for a given claim.
    /// @param claimId The claim id to get the total slash amount for.
    /// @return slashAmount The total amount slashed for the claim.
    function claimTotalSlashAmount(uint256 claimId) external view returns (uint256 slashAmount);

    /// @notice Get the ID representing the type of coverage provider
    /// @dev This is similar to a chain ID in blockchain nomenclature.
    /// @return providerTypeId The ID representing the type of coverage provider.
    function providerTypeId() external view returns (uint256 providerTypeId);
}
