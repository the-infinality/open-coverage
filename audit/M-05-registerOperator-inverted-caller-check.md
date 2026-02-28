# M-05: registerOperator Has Inverted Caller Check

## Audit Finding

**Severity:** Medium  
**Location:** `EigenServiceManagerFacet#registerOperator`  
**Status:** Resolved

### Description

The `registerOperator(...)` callback in `EigenServiceManagerFacet` was intended to be invoked by EigenLayer's `AllocationManager` during operator set registration. However, the implementation validated the wrong caller and used an inverted comparison:

```solidity
require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
```

This had two problems:
1. **Wrong contract:** It checked against `delegationManager` instead of `allocationManager`
2. **Inverted logic:** It used `!=` instead of `==`, meaning:
   - If `msg.sender == delegationManager`, it **reverted**
   - If `msg.sender` was **anyone else** (including attackers), it **passed**

### Impact

Attackers could repeatedly call `registerOperator` to reset an operator's custom `coverageThreshold` to the default value (7000), overriding operator risk configuration and causing threshold griefing/state tampering.

## Fix Applied

Changed the `require` statement to enforce strict caller validation against `allocationManager` with correct comparison logic.

**Before:**
```solidity
require(msg.sender != _eigenAddresses.delegationManager, "Not delegation manager");
```

**After:**
```solidity
require(msg.sender == _eigenAddresses.allocationManager, "Not allocation manager");
```

### Files Modified

- `src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol` — Fixed caller check in `registerOperator`
