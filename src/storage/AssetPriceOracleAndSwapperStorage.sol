// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAssetPriceOracleAndSwapperStorage} from "./LibAssetPriceOracleAndSwapperStorage.sol";
import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperStorage
/// @author p-dealwis, Infinality
/// @notice Diamond storage for the AssetPriceOracleAndSwapper facet
/// @dev Uses EIP-2535 diamond storage pattern via LibAssetPriceOracleAndSwapperStorage
abstract contract AssetPriceOracleAndSwapperStorage {
    using
    LibAssetPriceOracleAndSwapperStorage
    for LibAssetPriceOracleAndSwapperStorage.AssetPriceOracleAndSwapperStorage;

    /// @notice Get the asset pairs mapping
    /// @return The asset pairs mapping
    function assetPairs(bytes32 key) internal view returns (AssetPair storage) {
        return LibAssetPriceOracleAndSwapperStorage.assetPriceOracleAndSwapperStorage().assetPairs[key];
    }

    /// @notice Get the swap slippage
    /// @return The swap slippage in basis points
    function _swapSlippage() internal view returns (uint16) {
        LibAssetPriceOracleAndSwapperStorage.AssetPriceOracleAndSwapperStorage storage ds =
            LibAssetPriceOracleAndSwapperStorage.assetPriceOracleAndSwapperStorage();
        return ds.swapSlippage;
    }

    /// @notice Set the swap slippage
    /// @param slippage The swap slippage in basis points (0-10000)
    function _setSwapSlippage(uint16 slippage) internal {
        LibAssetPriceOracleAndSwapperStorage.AssetPriceOracleAndSwapperStorage storage ds =
            LibAssetPriceOracleAndSwapperStorage.assetPriceOracleAndSwapperStorage();
        ds.swapSlippage = slippage;
    }

    /// @notice Initialize the default swap slippage
    /// @dev Should be called during diamond construction to set default value
    function _initializeSwapSlippage() internal {
        LibAssetPriceOracleAndSwapperStorage.AssetPriceOracleAndSwapperStorage storage ds =
            LibAssetPriceOracleAndSwapperStorage.assetPriceOracleAndSwapperStorage();
        ds.swapSlippage = 100; // Default 1%
    }
}
