# M-04: `swapForOutput` built max input from wrong quote primitive

## Audit finding
Exact-output flow used reversed arguments and relied on an exact-input quote primitive, producing incorrect `amountInMax` and causing unnecessary reverts / slippage failures.

## Steps taken to fix
1. Corrected argument order in `swapForOutput`:
   - From `swapForOutputQuote(amountOut, assetB, assetA)`
   - To `swapForOutputQuote(amountOut, assetA, assetB)`
2. Extended `ISwapperEngine` with a native exact-output quote API:
   - `getQuoteForOutput(bytes poolInfo, uint256 amountOut, address base, address quote)`
3. Implemented `getQuoteForOutput` in `UniswapV3SwapperEngine` using `quoter.quoteExactOutput`.
4. Updated `swapForOutputQuote` to use `getQuoteForOutput` (or oracle path if configured), then apply configured slippage.
5. Updated tests to validate exact-output quote usage.

## Files updated
- `src/interfaces/ISwapperEngine.sol`
- `src/swapper-engines/UniswapV3SwapperEngine.sol`
- `src/mixins/AssetPriceOracleAndSwapper.sol`
- `test/mixins/AssetPriceOracleAndSwapper.t.sol`
- `test/swapper-engines/UniswapV3SwapperEngine.t.sol`
