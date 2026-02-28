# M-01: Spot Pricing and Unbounded Deadlines Expose Protocol Swaps to Sandwich Attacks

## Audit Finding

**Severity:** Medium  
**Location:** `UniswapV3SwapperEngine#swapForOutput`, `swapForInput`  
**Status:** Resolved

### Description

The protocol used momentary spot prices from the Uniswap V3 quoter to derive slippage protection parameters for protocol-initiated token swaps. This made swaps inherently vulnerable to sandwich attacks because an MEV attacker could skew the AMM price prior to the swap, and the protocol would fetch the manipulated spot price as its baseline quote, allowing slippage checks to pass on distorted metrics.

Additionally, the swaps executed with a transaction deadline hardcoded to `block.timestamp`, which dynamically resolves to the current block timestamp when the transaction is included — not when it was submitted. This provided no protection against delayed execution by validators, leaving transactions exposed to extreme market volatility.

### Impact

Immediate and recurring loss of protocol funds. Every high-value protocol-initiated swap was highly susceptible to sandwich attacks and volatile market conditions.

## Fix Applied

### 1. Oracle-Based Slippage Protection

Modified `swapForInputQuote` and `swapForOutputQuote` in `AssetPriceOracleAndSwapper.sol` to use oracle pricing when available (i.e., when a price oracle is configured and the price strategy is not `SwapperOnly`). This prevents same-block AMM manipulation from influencing slippage bounds.

**Before:**
```solidity
minAmountOut = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
```

**After:**
```solidity
if (_assetPair.priceStrategy != PriceStrategy.SwapperOnly && _assetPair.priceOracle != address(0)) {
    minAmountOut = IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, assetA, assetB);
} else {
    minAmountOut = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
}
```

### 2. Explicit Deadline Enforcement

Added a configurable `swapMaxDelay` storage variable (default: 300 seconds / 5 minutes) to `LibAssetPriceOracleAndSwapperStorage`. The deadline is computed as `block.timestamp + swapMaxDelay` and passed to the swapper engine.

**Changes:**
- Added `deadline` parameter to `ISwapperEngine.swapForInput` and `ISwapperEngine.swapForOutput`
- `UniswapV3SwapperEngine` now uses the passed deadline in `_getUniversalRouter().execute(commands, inputs, deadline)` instead of `block.timestamp`
- `AssetPriceOracleAndSwapper` computes deadline from `block.timestamp + _swapMaxDelay()` before each swap
- Added `setSwapMaxDelay` owner-only function to configure the max delay

### Files Modified

- `src/interfaces/ISwapperEngine.sol` — Added `deadline` parameter to swap functions
- `src/swapper-engines/UniswapV3SwapperEngine.sol` — Uses explicit deadline in router calls
- `src/mixins/AssetPriceOracleAndSwapper.sol` — Computes deadline, uses oracle for slippage
- `src/storage/LibAssetPriceOracleAndSwapperStorage.sol` — Added `swapMaxDelay` to storage struct
- `src/storage/AssetPriceOracleAndSwapperStorage.sol` — Added getter/setter for `swapMaxDelay`
- `src/interfaces/IAssetPriceOracleAndSwapper.sol` — Added `setSwapMaxDelay` and `swapMaxDelay`
- `src/facets/AssetPriceOracleAndSwapperFacet.sol` — Added `setSwapMaxDelay` owner function
