# M-02: Strategy Removal Can Block Claim Issuance

## Audit Finding

**Severity:** Medium  
**Location:** `EigenCoverageProviderFacet#issueClaim`  
**Status:** Resolved

### Description

The `issueClaim` function called `_validatePosition`, which enforced that `assetToStrategy[data.asset]` was still present in `_strategyWhitelist`. If governance removed a strategy from the whitelist after positions had already been created, `_validatePosition` would revert with `StrategyNotWhitelisted`, preventing any new claims from being issued against those still-active positions.

The root cause was that claim issuance for existing positions was coupled to a mutable whitelist check, even though the position was opened under previously valid conditions.

### Impact

Coverage agents could be unable to issue claims for still-active positions if the associated strategy was removed from the whitelist. This created a denial-of-service condition for legitimate claims and introduced governance-dependent liveness risk.

## Fix Applied

Removed the strategy whitelist check from `_validatePosition`. The whitelist is already validated at position creation time in `createPosition`, which has its own explicit whitelist check. Since the position was created under valid conditions, claims should remain issuable for the lifetime of the position regardless of subsequent whitelist changes.

**Before (`_validatePosition`):**
```solidity
function _validatePosition(CoveragePosition memory data, uint256 amount, uint256 duration, uint256 reward)
    private view
{
    uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
    if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);
    if (!_strategyWhitelist.contains(assetToStrategy[data.asset])) {
        revert IEigenOperatorProxy.StrategyNotWhitelisted(assetToStrategy[data.asset]);
    }
    // ...
}
```

**After:**
```solidity
function _validatePosition(CoveragePosition memory data, uint256 amount, uint256 duration, uint256 reward)
    private view
{
    uint256 minimumReward = (amount * data.minRate * duration) / (10000 * 365 days);
    if (minimumReward > reward) revert InsufficientReward(minimumReward, reward);
    // Whitelist check removed — already validated at position creation time
    // ...
}
```

### Files Modified

- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol` — Removed whitelist check from `_validatePosition`
