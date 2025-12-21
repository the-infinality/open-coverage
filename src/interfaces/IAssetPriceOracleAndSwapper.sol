// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Enum for swap engine types
enum SwapEngine {
    UNISWAP_V3,
    UNISWAP_V4_SINGLE_HOP
}

/// @notice Parameters for configuring a swap
struct SwapParams {
    SwapEngine swapEngine;
    bytes poolInfo;
}

/// @notice Uniswap V4 pool information
struct UniswapV4PoolInfo {
    PoolKey poolKey;
    bool zeroForOne;
}

/// @notice Asset pair configuration for price oracle and swapping
struct AssetPair {
    /// @notice The price oracle implementing the IPriceOracle
    address priceOracle;
    /// @notice The asset used to swap from
    address asset1;
    /// @notice The asset used to swap to
    address asset2;
    /// @notice The pool path to use for swapping via a configured SwapEngine
    SwapParams swapParams;
}

/// @title IAssetPriceOracleAndSwapper
/// @notice Interface for the asset price oracle and swapper facet
interface IAssetPriceOracleAndSwapper {
    error InvalidSwapEngine();
    error AssetPairNotRegistered();
    error InvalidPriceOracle();
    error InvalidAssetPair();
    error SliceOutOfBounds();

    /// @notice Registers a price adaptor for an asset pair
    /// @param priceOracle The price oracle address
    /// @param asset1 The first asset (swap from)
    /// @param asset2 The second asset (swap to)
    /// @param swapParams The swap parameters including engine and pool info
    function register(address priceOracle, address asset1, address asset2, SwapParams calldata swapParams)
        external;

    /// @notice Swaps an exact amount of output tokens
    /// @param amountOut The exact amount of tokens to receive
    /// @param asset1 The input asset
    /// @param asset2 The output asset
    function swap(uint128 amountOut, address asset1, address asset2) external;

    /// @notice Gets the asset pair configuration for two assets
    /// @param asset1 The first asset
    /// @param asset2 The second asset
    /// @return The asset pair configuration
    function assetPair(address asset1, address asset2) external view returns (AssetPair memory);

    /// @notice Gets a price quote for an asset pair
    /// @param amountIn The amount of the first asset
    /// @param asset1 The first asset
    /// @param asset2 The second asset
    /// @return The equivalent amount in the second asset
    function quote(uint256 amountIn, address asset1, address asset2) external view returns (uint256);
}

