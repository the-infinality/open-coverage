# M-03: swapForInput Passes Parameters in Reversed Order, Destroying Slippage Protection

## Audit Finding

**Severity:** Medium  
**Location:** `AssetPriceOracleAndSwapper#swapForInput`  
**Status:** Resolved

### Description

The `swapForInput` function in `AssetPriceOracleAndSwapper.sol` performed an exact-input swap using a minimum output amount derived from `swapForInputQuote`. However, it passed parameters to `swapForInputQuote` in reversed order, causing the slippage calculation to use incorrect exchange rates and token decimals.

The function signature of `swapForInputQuote` expects `(amountIn, assetA, assetB)` where `assetA` is the output token and `assetB` is the input token. But `swapForInput` passed `(amountIn, assetB, assetA)` — swapping the asset arguments.

### Impact

- **Case 1 (Zero Slippage Protection):** For swaps where the reversed calculation produced a tiny minimum output, the swap proceeded with essentially no slippage protection, enabling full MEV extraction.
- **Case 2 (Permanent DoS):** For swaps in the opposite direction, the reversed calculation demanded an impossibly large minimum output, causing all swaps to revert.

## Fix Applied

Corrected the parameter order in the `swapForInput` function.

**Before:**
```solidity
uint256 minAmountOut = swapForInputQuote(amountIn, assetB, assetA);
```

**After:**
```solidity
uint256 minAmountOut = swapForInputQuote(amountIn, assetA, assetB);
```

### Files Modified

- `src/mixins/AssetPriceOracleAndSwapper.sol` — Fixed parameter order in `swapForInput`
