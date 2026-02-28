# M-03: `swapForInput` used reversed quote parameters

## Audit finding
`swapForInput` passed `(assetB, assetA)` into `swapForInputQuote` instead of `(assetA, assetB)`, which broke slippage protection.

## Steps taken to fix
1. Corrected parameter order in `swapForInput`:
   - From `swapForInputQuote(amountIn, assetB, assetA)`
   - To `swapForInputQuote(amountIn, assetA, assetB)`
2. Updated tests to execute exact-input swaps using the corrected logic and deadline-aware API.

## Files updated
- `src/mixins/AssetPriceOracleAndSwapper.sol`
- `test/mixins/AssetPriceOracleAndSwapper.t.sol`
