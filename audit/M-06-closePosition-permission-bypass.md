# M-06: Whitelist removal bypassed closePosition permission checks

## Audit finding
`closePosition` only enforced operator authorization while strategy remained whitelisted. After strategy removal, authorization was skipped.

## Steps taken to fix
1. Removed whitelist-conditional authorization in `closePosition`.
2. Enforced operator permission checks unconditionally for position closure.
3. Updated tests to prove:
   - Unauthorized closure still reverts after strategy de-whitelisting
   - Authorized caller can still close position after de-whitelisting

## Files updated
- `src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol`
- `test/providers/eigenlayer/EigenCoverageProvider.t.sol`
