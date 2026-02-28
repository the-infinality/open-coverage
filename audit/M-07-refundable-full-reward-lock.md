# M-07: Refundable.Full rewards locked for slashed/repaid claims

## Audit finding
For `Refundable.Full`, rewards were only capturable in `Completed` status. Slashed claims moved to `Slashed`/`Repaid` and could not release rewards.

## Steps taken to fix
1. Expanded `captureRewards` eligibility for `Refundable.Full` claims to include `CoverageClaimStatus.Repaid`.
2. Added regression test for the lifecycle:
   - Issue claim with `Refundable.Full`
   - Slash claim
   - Fully repay claim
   - Verify `captureRewards` successfully releases the reward

## Files updated
- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol`
- `test/providers/eigenlayer/EigenCoverageProvider.t.sol`
