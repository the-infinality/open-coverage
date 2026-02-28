# M-02: Strategy removal could block claim issuance

## Audit finding
`issueClaim` depended on a dynamic whitelist check in `_validatePosition`. If governance removed a strategy after a position was created, claim issuance for that still-valid position reverted.

## Steps taken to fix
1. Removed dynamic strategy-whitelist enforcement from `_validatePosition`.
2. Kept whitelist checks at position creation time (`createPosition`) so only valid strategies can open positions.
3. Updated tests to verify claims and reservations remain usable for existing positions after strategy de-whitelisting.

## Files updated
- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol`
- `test/providers/eigenlayer/EigenCoverageProvider.t.sol`
