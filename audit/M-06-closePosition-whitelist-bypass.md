# M-06: Whitelist Removal Bypasses Operator Permission Check in closePosition

## Audit Finding

**Severity:** Medium  
**Location:** `EigenCoverageProviderFacet#closePosition`  
**Status:** Resolved

### Description

The `closePosition` function allowed a user to close an active coverage position before expiry. The operator permission check was wrapped in a condition that first checked `_strategyWhitelist.contains(strategy)`:

```solidity
if (
    _strategyWhitelist.contains(strategy)
        && !_checkOperatorPermissions(operator, ...)
) revert NotOperatorAuthorized(operator, msg.sender);
```

Due to short-circuit evaluation, if the strategy had been removed from `_strategyWhitelist`, the left side evaluated to `false` and `_checkOperatorPermissions` was never executed. This meant anyone could close positions without authorization when the associated strategy was removed from the whitelist.

### Impact

If a strategy was removed from the whitelist, position holders could close positions without any operator permission validation. This created inconsistent authorization behavior depending on mutable whitelist state.

## Fix Applied

Decoupled the operator permission check from whitelist membership. The permission check is now always enforced regardless of whether the strategy is in the whitelist. Also reordered the logic to check permissions before modifying state (setting `expiryTimestamp`).

**Before:**
```solidity
function closePosition(uint256 positionId) external {
    // ...
    address strategy = assetToStrategy[positionData.asset];
    positions[positionId].expiryTimestamp = block.timestamp;

    if (
        _strategyWhitelist.contains(strategy)
            && !_checkOperatorPermissions(operator, ...)
    ) revert NotOperatorAuthorized(operator, msg.sender);

    emit PositionClosed(positionId);
}
```

**After:**
```solidity
function closePosition(uint256 positionId) external {
    // ...
    if (
        !_checkOperatorPermissions(operator, ...)
    ) revert NotOperatorAuthorized(operator, msg.sender);

    positions[positionId].expiryTimestamp = block.timestamp;

    emit PositionClosed(positionId);
}
```

### Files Modified

- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol` — Removed whitelist condition from permission check in `closePosition`
