// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum PriceStrategy {
    OracleOnly,
    SwapperOnly,
    SwapperVerified
}

/// @notice Parameters for configuring a swap
struct SwapParams {
    address swapEngine;
    bytes poolInfo;
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

    error SwapFailed();
    error InvalidPoolInfo();
    error AssetPairNotRegistered();
    error InvalidPriceOracle();
    error PriceOracleRequired();
    error InvalidAssetPair();

    /// @notice Registers a price adaptor for an asset pair
    /// @param _assetPair The asset pair configuration
    function register(AssetPair calldata _assetPair) external;

    /// @notice Swaps an exact amount to receive output tokens specified
    /// @param amountOut The exact amount of tokens to receive
    /// @param assetA The input asset
    /// @param assetB The output asset
    function swapForOutput(uint128 amountOut, address assetA, address assetB) external;

    /// @notice Swaps an exact amount of input tokens
    /// @param amountIn The exact amount of tokens to spend
    /// @param assetA The input asset
    /// @param assetB The output asset
    function swapForInput(uint128 amountIn, address assetA, address assetB) external;

    /// @notice Gets the asset pair configuration for two assets
    /// @param assetA The first asset
    /// @param assetB The second asset
    /// @return The asset pair configuration
    function assetPair(address assetA, address assetB) external view returns (AssetPair memory);

    /// @notice Gets a price quote for an asset pair
    /// @param amountIn The amount of the first asset
    /// @param assetA The first asset
    /// @param assetB The second asset
    /// @return The equivalent amount in the second asset
    function quote(uint256 amountIn, address assetA, address assetB) external view returns (uint256);
}

