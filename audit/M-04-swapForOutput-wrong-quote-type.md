# M-04: swapForOutput Uses Reversed Exact-Input Quote Instead of Exact-Output Quote

## Audit Finding

**Severity:** Medium  
**Location:** `AssetPriceOracleAndSwapper#swapForOutput`  
**Status:** Resolved

### Description

The `swapForOutput` flow in `AssetPriceOracleAndSwapper.sol` needed to compute a safe `amountInMax` for an exact-output swap. Instead, it called `swapForOutputQuote` with reversed assets, which then used `ISwapperEngine.getQuote(...)` — an exact-input style quote.

This meant the system derived an exact-output bound from a reverse-direction exact-input simulation, which applied pool fees in the wrong mathematical direction. For a single pool with fee `f` and desired output `Y`:
- The correct exact-output input requirement is proportional to `Y / (1 - f)`
- The reversed exact-input quote returns proportional to `Y * (1 - f)`

The estimated max input was short by a factor of `(1 - f)^2`, causing systematic underfunding.

Additionally, the parameter order in the `swapForOutput` call to `swapForOutputQuote` was reversed.

### Impact

Exact-output swaps could revert even when market conditions were normal because `amountInMax` was systematically too low. This caused denial of service for protocol flows relying on exact-output settlement (e.g., fixed debt repayment, fixed-size position adjustments).

## Fix Applied

### 1. Added Exact-Output Quote Function

Added `getQuoteForOutput` to `ISwapperEngine` interface and implemented it in `UniswapV3SwapperEngine` using the Uniswap V3 quoter's `quoteExactOutput` function, which correctly computes the input amount required for a desired output.

```solidity
function getQuoteForOutput(bytes memory poolInfo, uint256 amountOut, address base, address quote)
    external view returns (uint256 amountIn);
```

### 2. Fixed swapForOutputQuote

Updated `swapForOutputQuote` to use the new `getQuoteForOutput` function (or oracle pricing when available) instead of the exact-input `getQuote`.

**Before:**
```solidity
maxAmountIn = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountOut, assetA, assetB);
```

**After:**
```solidity
if (_assetPair.priceStrategy != PriceStrategy.SwapperOnly && _assetPair.priceOracle != address(0)) {
    maxAmountIn = IPriceOracle(_assetPair.priceOracle).getQuote(amountOut, assetB, assetA);
} else {
    maxAmountIn = ISwapperEngine(_assetPair.swapEngine).getQuoteForOutput(
        _assetPair.poolInfo, amountOut, assetA, assetB
    );
}
```

### 3. Fixed Parameter Order in swapForOutput

**Before:**
```solidity
uint256 maxAmountIn = swapForOutputQuote(amountOut, assetB, assetA);
```

**After:**
```solidity
uint256 maxAmountIn = swapForOutputQuote(amountOut, assetA, assetB);
```

### Files Modified

- `src/interfaces/ISwapperEngine.sol` — Added `getQuoteForOutput` function
- `src/swapper-engines/UniswapV3SwapperEngine.sol` — Implemented `getQuoteForOutput` using `quoteExactOutput`
- `src/mixins/AssetPriceOracleAndSwapper.sol` — Fixed parameter order and quote type in `swapForOutput` and `swapForOutputQuote`
