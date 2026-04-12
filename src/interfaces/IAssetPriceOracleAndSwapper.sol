// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum PriceStrategy {
    /// @notice Only use the oracle to get the quote
    OracleOnly,
    /// @notice Only use the swapper to get the quote
    SwapperOnly,
    /// @notice Use the swapper to get the quote and verify it with the oracle
    SwapperVerified,
    /// @notice Use the oracle to get the quote and verify it with the swapper
    OracleVerified
}

/// @notice Asset pair configuration for price oracle and swapping
struct AssetPair {
    /// @notice First asset in the registered pair (order is arbitrary; see `assetPair` / quoting params)
    address assetA;
    /// @notice Second asset in the registered pair (order is arbitrary; see `assetPair` / quoting params)
    address assetB;
    /// @notice The swap engine to use for swapping
    address swapEngine;
    /// @notice The pool information to use for swapping
    bytes poolInfo;
    /// @notice The price strategy to use for the asset pair
    PriceStrategy priceStrategy;
    /// @notice The accuracy of the swapper
    /// @dev This is the accuracy of the swapper in basis points i.e. 1 = 0.01%
    uint16 swapperAccuracy;
    /// @notice Optional price oracle implementing the IPriceOracle
    /// @dev If not set, the price strategy must be SwapperOnly and swapperAccuracy must be 0
    address priceOracle;
}

/// @title IAssetPriceOracleAndSwapper
/// @notice Interface for the asset price oracle and swapper facet
/// @dev `getQuote` matches `IPriceOracle.getQuote(amountIn, base, quote)` (returned amount is `quote` units).
/// Swap entrypoints align with `ISwapperEngine` (`base` = asset received, `swap` = asset spent).
/// Registration order (`AssetPair.assetA` / `assetB`) is independent of these axes; lookups accept either token order
/// because the implementation resolves the stored pair by `(assetA, assetB)` or the reversed tuple.
interface IAssetPriceOracleAndSwapper {
    event AssetPairRegistered(address assetA, address assetB);

    error PriceMismatch();
    error SwapFailed();
    error InvalidPoolInfo();
    error AssetPairNotRegistered();
    error PriceOracleRequired();
    error InvalidAssetPair();
    error InvalidSwapperAccuracy();
    error InvalidSwapSlippage();
    error ExceedsMaxDeadline(uint256 maxDeadline, uint256 givenDeadline);

    /// @notice Registers a price adaptor for an asset pair
    /// @param _assetPair The asset pair configuration
    function register(AssetPair calldata _assetPair) external;

    /// @notice Swaps to receive an exact output amount (same `base` / `swap` roles as `ISwapperEngine.swapForOutput`)
    /// @param amountOut Exact amount of `base` to receive
    /// @param base Asset received; `swapForOutputQuote` prices via `getQuote(amountOut, swap, base)` (`IPriceOracle`-style args)
    /// @param swap Asset spent
    function swapForOutput(uint256 amountOut, address base, address swap, uint256 deadline) external;

    /// @notice Swaps an exact input amount for at least a minimum output (same `base` / `swap` roles as `ISwapperEngine.swapForInput`)
    /// @param amountIn Exact amount of `swap` to spend
    /// @param base Asset received; priced with `getQuote(amountIn, base, swap)`
    /// @param swap Asset spent
    function swapForInput(uint256 amountIn, address base, address swap, uint256 deadline) external;

    /// @notice Sets the swap slippage
    /// @param swapSlippage_ The swap slippage in basis points i.e. 1 = 0.01%
    function setSwapSlippage(uint16 swapSlippage_) external;

    /// @notice Sets the maximum deadline offset for a swap (duration in seconds from block.timestamp)
    /// @param maxDeadlineOffset_ The maximum deadline offset for a swap
    function setMaxDeadlineOffset(uint256 maxDeadlineOffset_) external;

    /// @notice Gets the asset pair configuration for two assets
    /// @param assetA First address used to look up the pair (need not match stored `AssetPair.assetA`; order may be reversed)
    /// @param assetB Second address used to look up the pair
    /// @return The asset pair configuration as stored (fixed `assetA` / `assetB` registration order)
    function assetPair(address assetA, address assetB) external view returns (AssetPair memory);

    /// @notice Gets the swap slippage
    /// @return The swap slippage
    function swapSlippage() external view returns (uint16);

    /// @notice Gets the maximum deadline offset for a swap (duration in seconds from block.timestamp)
    /// @return The maximum deadline offset for a swap
    function maxDeadlineOffset() external view returns (uint256);

    /// @notice Same signature as `IPriceOracle.getQuote`: `outAmount` of `quote` for `amountIn` of `base`
    /// @param amountIn Amount of `base` (see `IPriceOracle.getQuote`)
    /// @param base The base asset (`IPriceOracle` `base` parameter)
    /// @param quote The quote asset (`IPriceOracle` `quote` parameter)
    /// @return outAmount Amount of `quote` equivalent to `amountIn` of `base` (before facet slippage in swap helpers)
    /// @return verified Whether the quote has been verified by an oracle (if applicable)
    function getQuote(uint256 amountIn, address base, address quote)
        external
        view
        returns (uint256 outAmount, bool verified);

    /// @notice Maximum `swap` to spend for exactly `amountOut` of `base`: internally `getQuote(amountOut, swap, base)`
    /// @param amountOut Target amount of `base` to receive
    /// @param base Asset received (`quote` token in the internal `getQuote` call)
    /// @param swap Asset spent (`base` token in the internal `getQuote` call)
    /// @return maxAmountIn Upper bound on `swap` needed (includes facet slippage padding)
    /// @return verified Whether the quote has been verified based on the price strategy
    function swapForOutputQuote(uint256 amountOut, address base, address swap)
        external
        view
        returns (uint256 maxAmountIn, bool verified);

    /// @notice Minimum `base` received for spending `amountIn` of `swap`: internally `getQuote(amountIn, base, swap)`
    /// @param amountIn Exact amount of `swap` to spend
    /// @param base Asset received
    /// @param swap Asset spent
    /// @return minAmountOut Minimum `base` after facet slippage discount
    /// @return verified Whether the quote has been verified based on the price strategy
    function swapForInputQuote(uint256 amountIn, address base, address swap)
        external
        view
        returns (uint256 minAmountOut, bool verified);
}
