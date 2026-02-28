# M-07: Rewards Locked for Slashed Refundable.Full Claims

## Audit Finding

**Severity:** Medium  
**Location:** `EigenCoverageProviderFacet#closeClaim`, `captureRewards`  
**Status:** Resolved

### Description

`Refundable.Full` rewards were only released when a claim reached `Completed` status. However, slashing moved a claim to `Slashed` status, and there was no transition from `Slashed` or `Repaid` to `Completed`. This left the reward held by the Diamond contract with no release path.

The specific lifecycle gaps:
- `closeClaim(...)` only accepted `Issued` or `Reserved` status, so a `Slashed` claim could not be completed
- `captureRewards(...)` only released rewards for `Refundable.Full` when status was `Completed`
- `repaySlashedClaim(...)` could move `Slashed` → `Repaid`, but did not complete the claim or release the reward

Additionally, `captureRewards` lacked a guard against `Reserved` claims, which are unfunded (no reward tokens transferred). This was noted in the related H-03 finding.

### Impact

Rewards for `Refundable.Full` claims that got slashed could not be released to either party. The funds remained permanently stuck in the Diamond contract.

## Fix Applied

### 1. Extended Reward Eligibility for Slashed/Repaid Claims

Modified the `captureRewards` function to accept `Slashed` and `Repaid` statuses for `Refundable.Full` claims, in addition to the existing `Completed` status. This provides a terminal path for reward release when a claim is slashed.

**Before:**
```solidity
if (
    _position.refundable == Refundable.None ||
    (_position.refundable == Refundable.Full && _claim.status == CoverageClaimStatus.Completed)
) {
    amount = _claim.reward - _claimRewardDistribution.amount;
    // ...
}
```

**After:**
```solidity
if (
    _position.refundable == Refundable.None
    || (_position.refundable == Refundable.Full
        && (_claim.status == CoverageClaimStatus.Completed
            || _claim.status == CoverageClaimStatus.Slashed
            || _claim.status == CoverageClaimStatus.Repaid))
) {
    amount = _claim.reward - _claimRewardDistribution.amount;
    // ...
}
```

### 2. Added Guard Against Reserved (Unfunded) Claims

Added an early return for `Reserved` claims at the top of `captureRewards` to prevent reward capture on unfunded claims. This serves as defense-in-depth against the related H-03 finding.

```solidity
if (_claim.status == CoverageClaimStatus.Reserved) {
    return (0, 0, distributionStartTime);
}
```

### Files Modified

- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol` — Extended reward eligibility in `captureRewards` for slashed/repaid Full claims; added Reserved claim guard
