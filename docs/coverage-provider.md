# CoverageProvider

## Links

- [Interface](../src/interfaces/ICoverageProvider.sol)

## Overview

The CoverageProvider is the contract responsible for backing coverage positions with real assets and managing the claims lifecycle. It acts as the bridge between restaking infrastructure (operators/delegators) and coverage agents, allowing positions to be created, claims to be issued or reserved, and slashing to be enforced when obligations are not met. Each provider can support multiple coverage positions, each tied to a specific coverage agent, asset, and set of parameters such as rate, duration, and refund policy.


## Mechanisms

### Coverage Position

A Coverage Position is a guarantee from the Coverage Provider to provide coverage within their given parameters. This is used to provide coverage for a specific coverage agent, asset provided for coverage, minimum rate, maximum duration, expiry timestamp, slash coordinator and refund policy.

### Coverage Claim

A Coverage Claim is a request for coverage from the Coverage Provider on a pre-created Coverage Position. Only the Coverage Agent on the Coverage Position should be able to issue a claim against the position and must pay fees upfront for the claim based on the minimum rate. Once issued, the claim is considered to be active and the Coverage Provider is obligated to provide coverage for the claim.

### Reward Distribution

The CoverageProvider contract implements a reward distribution mechanism that allows operators to claim their rewards over time. The mechanism is designed to be flexible and can be configured to suit different use cases.

There are 3 different refund policies that can be configured for a coverage position and each have different behaviours for rewards capture, early claim close and claim liquidations.

**Behaviour by policy:**

| Policy | Early close (via `closeClaim`) | Liquidation (via `liquidateClaim`) | Reward distribution (via `captureRewards`) |
|---|---|---|---|
| `None` | No refund. The operator retains the full reward regardless of how early the claim is closed. | No refund. | The full reward is available to the operator immediately after issuance. The first `captureRewards` call (in any block after the issuance block) releases the entire reward at once - there is no time-gating. |
| `TimeWeighted` | Time-proportional refund. The unused portion of the reward (`reward * remainingTime / totalDuration`) is returned to the coverage agent. | Time-proportional refund based on how long the position has been open. | Rewards are streamed progressively to the operator over the claim duration. Each `captureRewards` call releases rewards proportional to elapsed time (`elapsedTime * reward / duration`), minus any amount already distributed. |
| `Full` | Time-proportional refund (same formula as `TimeWeighted`). Despite the name, a 100% refund only applies during liquidation, not on early close. | Full 100% refund of the reward, allowing the coverage agent to re-purchase coverage for the remaining duration elsewhere. | No progressive distribution. Rewards are held in full until the claim reaches `Completed` status (i.e. closed after its duration elapses). `captureRewards` returns nothing while the claim is active. |

### Liquidations

Liquidations are a mechanism to force the coverage agent to give up their risk coverage claim if the position no longer meets its obligations. This is will occur if the coverage provider can not meet the liquidity requirements of the claim and will involve another coverage provider entity taking over the claim by pointing towards their coverage position instead. Based on the implementation of the Coverage Provider this may also involve requiring the new entities position to use the same or similar assets (asset equivalence check needs to be implemented).

### Slashings

Slashing is the mechanism utilised by the Coverage Agent to ensure the Coverage Provider pays out on the claim in the event of a risk coverage execution condition being met. Each Coverage Provider will have its own slashing mechanism, however, a Slashing Coordinator custom logic class may be implemented to further supplement the slashing process, such as an implementation of a voting process.

## Data Structures

### CoveragePosition

Defines the parameters of a coverage position offered by the provider.

```solidity
struct CoveragePosition {
    address coverageAgent;
    uint16 minRate;
    uint256 maxDuration;
    uint256 expiryTimestamp;
    address asset;
    Refundable refundable;
    address slashCoordinator;
    uint256 maxReservationTime;
    bytes32 operatorId;
}
```

### CoverageClaim

Represents an individual claim against a coverage position.

```solidity
struct CoverageClaim {
    uint256 positionId;
    uint256 amount;
    uint256 duration;
    uint256 createdAt;
    CoverageClaimStatus status;
    uint256 reward;
}
```

### Refundable

Defines the refund policy for a coverage position's reward when a claim is closed early or liquidated. The policy affects both how rewards are streamed to operators over the claim's lifetime and what happens to unreleased rewards.

```solidity
enum Refundable {
    None,         // No reward refund
    TimeWeighted, // Refund reward based on time position has been open
    Full          // Full refund of reward on liquidation
}
```

### CoverageClaimStatus

Tracks the lifecycle state of a coverage claim.

```solidity
enum CoverageClaimStatus {
    Issued,
    Completed,
    PendingSlash,
    Slashed,
    Reserved,
    Repaid
}
```

## Specification

### Hooks

#### onIsRegistered

Callback triggered when the coverage provider is registered with a coverage agent.

```solidity
function onIsRegistered() external;
```

### Coverage Positions

#### createPosition

Creates a new coverage position and registers it with the specified coverage agent.

```solidity
function createPosition(CoveragePosition memory data, bytes calldata additionalData) external returns (uint256 positionId);
```

#### closePosition

Closes an existing coverage position.

```solidity
function closePosition(uint256 positionId) external;
```

### Coverage Claims

#### issueClaim

Issues a coverage claim against a position. The caller should approve the coverage provider to transfer the reward.

```solidity
function issueClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward) external returns (uint256 claimId);
```

#### reserveClaim

Reserves coverage without immediately requiring the full reward payment. The reservation can be converted to an issued claim within the `maxReservationTime`.

```solidity
function reserveClaim(uint256 positionId, uint256 amount, uint256 duration, uint256 reward) external returns (uint256 claimId);
```

#### convertReservedClaim

Converts a reserved claim to an issued claim. The amount and duration can be less than or equal to the reserved amounts.

```solidity
function convertReservedClaim(uint256 claimId, uint256 amount, uint256 duration, uint256 reward) external;
```

#### closeClaim

Closes a coverage claim and transitions it to `Completed` status. Access and behaviour depend on claim state and caller:

- **Expired reservations** (`createdAt + maxReservationTime < block.timestamp`): Anyone can close. The reserved coverage amount is released back to the position with no reward transfer (rewards were never collected for reservations).
- **Elapsed issued claims** (`createdAt + duration <= block.timestamp`): Anyone can close. The full duration has been served, so no refund is issued regardless of refund policy.
- **Early close by coverage agent** (`block.timestamp < expiresAt`): Only the coverage agent that owns the claim may close it before expiry. When an issued claim is closed early, the refund policy on the position determines what happens to the remaining reward:
  - `Refundable.None` -- No refund. The operator retains the full reward.
  - `Refundable.TimeWeighted` -- A time-proportional refund is calculated as `reward * remainingTime / totalDuration` and returned to the coverage agent via `onClaimRefunded`. The claim's stored reward and duration are reduced to reflect actual usage.
  - `Refundable.Full` -- Same time-proportional refund as `TimeWeighted` on early close (a full 100% refund only applies during liquidation). The claim's stored reward and duration are reduced to reflect actual usage.

All other callers attempting to close a non-expired claim will be reverted with `ClaimNotExpired`.

```solidity
function closeClaim(uint256 claimId) external;
```

#### liquidateClaim

Liquidates a coverage claim when the backing position no longer meets its obligations (e.g. due to operator deallocation or slashing that creates a coverage deficit). This is the mechanism through which the `Refundable.Full` policy differs from `TimeWeighted` -- on liquidation, the entire remaining reward is refunded to the coverage agent so it can re-purchase equivalent coverage elsewhere.

```solidity
function liquidateClaim(uint256 claimId) external;
```

#### slashClaims

Slashes one or more coverage claims. Can only be called by a coverage agent. Takes a slash coordinator into account if one is set on the position.

```solidity
function slashClaims(uint256[] calldata claimIds, uint256[] calldata amounts) external returns (CoverageClaimStatus[] memory slashStatuses);
```

#### completeSlash

Completes the slashing process for a claim. Can only be called by the slash coordinator that initiated the process.

```solidity
function completeSlash(uint256 claimId) external;
```

#### repaySlashedClaim

Repays a claim that has been slashed. Can only be called by the coverage agent that issued the claim.

```solidity
function repaySlashedClaim(uint256 claimId, uint256 amount) external;
```

### Discovery

#### position

Returns the coverage position for a given position id.

```solidity
function position(uint256 positionId) external view returns (CoveragePosition memory position);
```

#### positionMaxAmount

Returns the maximum amount of coverage available for a given position.

```solidity
function positionMaxAmount(uint256 positionId) external view returns (uint256 maxAmount);
```

#### claim

Returns the coverage claim for a given claim id.

```solidity
function claim(uint256 claimId) external view returns (CoverageClaim memory claim);
```

#### positionBacking

Returns the total available backing for a position. A negative value indicates a backing deficit, while a positive value means the position is fully backed.

```solidity
function positionBacking(uint256 positionId) external view returns (int256 backing, uint16 coveragePercentage);
```

#### claimTotalSlashAmount

Returns the total amount slashed for a given claim.

```solidity
function claimTotalSlashAmount(uint256 claimId) external view returns (uint256 slashAmount);
```

#### providerTypeId

Returns the ID representing the type of coverage provider, similar to a chain ID in blockchain nomenclature.

```solidity
function providerTypeId() external view returns (uint256 providerTypeId);
```

### Events

| Event | Description |
|---|---|
| `PositionCreated(uint256 indexed positionId)` | Emitted when a new coverage position is created. |
| `PositionClosed(uint256 indexed positionId)` | Emitted when a coverage position is closed. |
| `ClaimIssued(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration)` | Emitted when a coverage claim is issued against a position. |
| `ClaimReserved(uint256 indexed positionId, uint256 indexed claimId, uint256 amount, uint256 duration)` | Emitted when coverage is reserved against a position. |
| `ClaimClosed(uint256 indexed claimId)` | Emitted when a claim is closed. |
| `ClaimLiquidated(uint256 indexed claimId)` | Emitted when a claim is liquidated. |
| `ClaimSlashed(uint256 indexed claimId, uint256 amount)` | Emitted when a claim is slashed. |
| `ClaimSlashPending(uint256 indexed claimId, address slashCoordinator)` | Emitted when a slash is initiated and pending coordinator approval. |
| `ClaimRepayment(uint256 indexed claimId, uint256 amount)` | Emitted when a partial repayment is made on a slashed claim. |
| `ClaimRepaid(uint256 indexed claimId)` | Emitted when a slashed claim is fully repaid. |
| `MetadataUpdated(string metadataUri)` | Emitted when the provider's metadata URI is updated. |

### Errors

| Error | Description |
|---|---|
| `ZeroAmount()` | The provided amount is zero. |
| `PositionExpired(uint256 positionId, uint256 expiredAt)` | The coverage position has expired. |
| `TimestampInvalid(uint256 timestamp)` | The provided timestamp is invalid. |
| `MinRateInvalid(uint16 minRate)` | The provided minimum rate is invalid. |
| `NotCoverageAgent(address caller, address required)` | The caller is not the expected coverage agent. |
| `InsufficientReward(uint256 minimumReward, uint256 reward)` | The provided reward is below the minimum required. |
| `InsufficientCoverageAvailable(uint256 deficit)` | There is not enough coverage available to fulfil the request. |
| `DurationExceedsMax(uint256 maxDuration, uint256 duration)` | The requested duration exceeds the position's maximum. |
| `DurationExceedsExpiry(uint256 expiryTimestamp, uint256 completionTimestamp)` | The claim would complete after the position expires. |
| `InvalidClaim(uint256 claimId, CoverageClaimStatus currentStatus)` | The claim is in an invalid state for the requested operation. |
| `SlashFailed(uint256 claimId)` | The slash operation failed. |
| `SlashAmountExceedsClaim(uint256 claimId, uint256 slash, uint256 claim)` | The slash amount exceeds the claim amount. |
| `ReservationNotAllowed(uint256 positionId)` | Reservations are not allowed on this position. |
| `ReservationExpired(uint256 claimId, uint256 expiredAt)` | The reservation has expired. |
| `AmountExceedsReserved(uint256 claimId, uint256 amount, uint256 reserved)` | The requested amount exceeds the reserved amount. |
| `DurationExceedsReserved(uint256 claimId, uint256 duration, uint256 reserved)` | The requested duration exceeds the reserved duration. |
| `ClaimNotReserved(uint256 claimId)` | The claim is not in a reserved state. |
| `ClaimNotExpired(uint256 claimId, uint256 expiresAt)` | The claim has not yet expired. |
| `ClaimExpired(uint256 claimId, uint256 expiredAt)` | The claim has already expired. |
