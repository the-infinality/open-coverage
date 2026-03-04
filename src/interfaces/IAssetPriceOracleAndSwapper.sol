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
    /// @notice The first asset in the pair
    address assetA;
    /// @notice The second asset in the pair
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

    /// @notice Swaps an exact amount to receive output tokens specified
    /// @param amountOut The exact amount of `assetA` tokens to receive
    /// @param assetA The asset to receive (output/base)
    /// @param assetB The asset to spend (input/swap)
    function swapForOutput(uint256 amountOut, address assetA, address assetB, uint256 deadline) external;

    /// @notice Swaps an exact amount of input tokens
    /// @param amountIn The exact amount of `assetB` tokens to spend
    /// @param assetA The asset to receive (output/base)
    /// @param assetB The asset to spend (input/swap)
    function swapForInput(uint256 amountIn, address assetA, address assetB, uint256 deadline) external;

    /// @notice Sets the swap slippage
    /// @param swapSlippage_ The swap slippage in basis points i.e. 1 = 0.01%
    function setSwapSlippage(uint16 swapSlippage_) external;

    /// @notice Sets the maximum deadline offset for a swap (duration in seconds from block.timestamp)
    /// @param maxDeadlineOffset_ The maximum deadline offset for a swap
    function setMaxDeadlineOffset(uint256 maxDeadlineOffset_) external;

    /// @notice Gets the asset pair configuration for two assets
    /// @param assetA The first asset
    /// @param assetB The second asset
    /// @return The asset pair configuration
    function assetPair(address assetA, address assetB) external view returns (AssetPair memory);

    /// @notice Gets the swap slippage
    /// @return The swap slippage
    function swapSlippage() external view returns (uint16);

    /// @notice Gets the maximum deadline offset for a swap (duration in seconds from block.timestamp)
    /// @return The maximum deadline offset for a swap
    function maxDeadlineOffset() external view returns (uint256);

    /// @notice Gets a price quote for an asset pair
    /// @param amountIn The amount of `assetB` to get value for `assetA`
    /// @param assetA The asset to quote the value for (output/base)
    /// @param assetB The asset to get value from (input/swap)
    /// @return quote The equivalent amount of `assetA` for `amountIn` of `assetB`
    /// @return verified Whether the quote has been verified by an oracle (if applicable)
    function getQuote(uint256 amountIn, address assetA, address assetB)
        external
        view
        returns (uint256 quote, bool verified);

    /// @notice Gets the maximum amount of `assetB` tokens that can be spent to receive `amountOut` of `assetA`
    /// @param amountOut The exact amount of `assetA` tokens to receive
    /// @param assetA The asset to receive (output/base)
    /// @param assetB The asset to spend (input/swap)
    /// @return maxAmountIn The maximum amount of `assetB` tokens that can be spent
    /// @return verified Whether the quote has been verified based on the price strategy
    function swapForOutputQuote(uint256 amountOut, address assetA, address assetB)
        external
        view
        returns (uint256 maxAmountIn, bool verified);

    /// @notice Gets the minimum amount of `assetA` tokens that can be received for `amountIn` of `assetB`
    /// @param amountIn The exact amount of `assetB` tokens to spend
    /// @param assetA The asset to receive (output/base)
    /// @param assetB The asset to spend (input/swap)
    /// @return minAmountOut The minimum amount of `assetA` tokens that can be received
    /// @return verified Whether the quote has been verified based on the price strategy
    function swapForInputQuote(uint256 amountIn, address assetA, address assetB)
        external
        view
        returns (uint256 minAmountOut, bool verified);
}
