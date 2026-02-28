# M-01: Spot pricing + unbounded swap deadlines

## Audit finding
Protocol swaps relied on immediate on-chain quote state and used `block.timestamp` directly in router execution, which provided no bounded expiry window from the caller perspective.

## Steps taken to fix
1. Added an explicit `deadline` argument to:
   - `IAssetPriceOracleAndSwapper.swapForInput`
   - `IAssetPriceOracleAndSwapper.swapForOutput`
   - `ISwapperEngine.swapForInput`
   - `ISwapperEngine.swapForOutput`
2. Added strict deadline validation in `AssetPriceOracleAndSwapper`:
   - Revert if deadline is in the past (`SwapDeadlineExpired`)
   - Revert if deadline is more than 15 minutes ahead (`SwapDeadlineTooFar`)
3. Wired the supplied deadline through delegatecalls into `UniswapV3SwapperEngine`.
4. Updated router execution in `UniswapV3SwapperEngine` to use the provided deadline instead of `block.timestamp`.
5. Hardened quote source selection in quote helpers:
   - If an oracle exists for the pair, use oracle-derived pricing for slippage bounds.
   - Fall back to swapper quotes only when oracle is not configured.

## Files updated
- `src/interfaces/IAssetPriceOracleAndSwapper.sol`
- `src/interfaces/ISwapperEngine.sol`
- `src/mixins/AssetPriceOracleAndSwapper.sol`
- `src/swapper-engines/UniswapV3SwapperEngine.sol`
- `test/mixins/AssetPriceOracleAndSwapper.t.sol`
- `test/swapper-engines/UniswapV3SwapperEngine.t.sol`
