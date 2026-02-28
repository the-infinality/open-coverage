# M-05: `registerOperator` had inverted/incorrect caller validation

## Audit finding
`registerOperator` checked the wrong caller and used inverted logic, allowing unauthorized callers while rejecting the intended system caller.

## Steps taken to fix
1. Replaced caller guard with strict AllocationManager validation:
   - `require(msg.sender == _eigenAddresses.allocationManager, "Not allocation manager");`
2. Updated tests to cover:
   - Success when called by AllocationManager
   - Revert when called by non-AllocationManager
   - Revert when called by DelegationManager
   - Invalid AVS path under correct caller context

## Files updated
- `src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol`
- `test/providers/eigenlayer/EigenServiceManager.t.sol`
- `test/providers/eigenlayer/EigenPermissions.t.sol`
- `test/providers/eigenlayer/EigenCoverageProvider.t.sol`
