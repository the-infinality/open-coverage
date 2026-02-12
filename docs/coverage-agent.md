# CoverageAgent

## Links

- [Interface](src/interfaces/ICoverageAgent.sol)
- [Example Implementation](src/ExampleCoverageAgent.sol)

## Overview

The CoverageAgent is the core contract that manages the lifecycle of coverage positions. It acts as the intermediary between a coordinator and one or more coverage providers, handling registration of providers, purchasing and reserving coverage, slashing, and repayment. Coverage is denominated in a single ERC20 asset, which is also used to pay rewards to coverage providers.

## Data Structures

### ClaimCoverageRequest

A request to claim coverage from a specific coverage provider.

```solidity
struct ClaimCoverageRequest {
    address coverageProvider;
    uint256 positionId;
    uint256 amount;
    uint256 reward;
    uint256 duration;
}
```

### Claim

A record of an individual claim issued by a coverage provider.

```solidity
struct Claim {
    address coverageProvider;
    uint256 claimId;
}
```

### Coverage

Aggregates all claims under a single coverage id and tracks whether it is a reservation.

```solidity
struct Coverage {
    Claim[] claims;
    bool reservation;
}
```

## Specification

### Coverage Providers

#### registerCoverageProvider

Registers a coverage provider with the agent. Can only be called by the coordinator.

```solidity
function registerCoverageProvider(address coverageProvider) external;
```

#### onRegisterPosition

Callback triggered when a coverage position has been registered with a coverage provider. A coverage position is a guarantee from the provider to supply coverage within their given parameters.

```solidity
function onRegisterPosition(uint256 positionId) external;
```

#### onSlashCompleted

Callback triggered when a coverage claim has been slashed. Can only be called by the coverage provider that issued the claim.

```solidity
function onSlashCompleted(uint256 claimId, uint256 slashAmount) external;
```

#### onClaimRefunded

Callback triggered when a coverage claim has been refunded due to early closure. Can only be called by the coverage provider that issued the claim.

```solidity
function onClaimRefunded(uint256 claimId, uint256 refundAmount) external;
```

### Discovery

#### registeredCoverageProviders

Returns all coverage providers registered with the agent.

```solidity
function registeredCoverageProviders() external view returns (address[] memory coverageProviderAddresses);
```

#### isCoverageProviderRegistered

Checks whether a given coverage provider is registered with the agent.

```solidity
function isCoverageProviderRegistered(address coverageProvider) external view returns (bool isRegistered);
```

#### coverage

Returns the coverage data for a given coverage id, including all associated claims and reservation status.

```solidity
function coverage(uint256 coverageId) external view returns (Coverage memory coverage);
```

#### asset

Returns the ERC20 asset that the coverage agent requires coverage on. Rewards are paid in this asset.

```solidity
function asset() external view returns (address);
```

### Events

| Event | Description |
|---|---|
| `CoverageProviderRegistered(address indexed coverageProvider)` | Emitted when a coverage provider is registered. |
| `CoverageClaimed(uint256 indexed coverageId)` | Emitted when coverage is purchased or a reservation is converted. |
| `CoverageReserved(uint256 indexed coverageId)` | Emitted when coverage is reserved. |
| `CoverageSlashed(uint256 indexed coverageId)` | Emitted when coverage is slashed. |
| `CoverageRepaid(uint256 indexed coverageId)` | Emitted when slashed coverage is fully repaid. |
| `MetadataUpdated(string metadataUri)` | Emitted when the agent's metadata URI is updated. |

### Errors

| Error | Description |
|---|---|
| `InvalidCoverage(uint256 coverageId)` | The given coverage id does not exist. |
| `CoverageProviderNotRegistered()` | The caller or specified address is not a registered coverage provider. |
| `CoverageNotReservation(uint256 coverageId)` | The coverage id does not correspond to a reservation. |
| `CoverageAlreadyConverted(uint256 coverageId)` | The reservation has already been converted to issued coverage. |
