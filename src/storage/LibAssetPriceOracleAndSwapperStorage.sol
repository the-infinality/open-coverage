// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title LibAssetPriceOracleAndSwapperStorage
/// @author p-dealwis, Infinality
/// @notice Library for diamond storage pattern for AssetPriceOracleAndSwapper
/// @dev Uses EIP-2535 diamond storage pattern to avoid storage collisions
library LibAssetPriceOracleAndSwapperStorage {
    /// @notice Storage position for AssetPriceOracleAndSwapper storage
    bytes32 constant ASSET_PRICE_ORACLE_AND_SWAPPER_STORAGE_POSITION =
        keccak256("asset.price.oracle.and.swapper.storage");

    /// @notice Storage structure for AssetPriceOracleAndSwapper
    struct AssetPriceOracleAndSwapperStorage {
        /// @notice Mapping from asset pair hash to asset pair configuration
        mapping(bytes32 => AssetPair) assetPairs;
        /// @notice The swap slippage in basis points i.e. 1 = 0.01%
        /// @dev Default slippage is 100 (1%), initialized in constructor
        uint16 swapSlippage;
        /// @notice The maximum deadline offset for a swap (duration in seconds from block.timestamp)
        uint256 maxDeadlineOffset;
    }

    /// @notice Get the diamond storage for AssetPriceOracleAndSwapper
    /// @return ds Storage pointer
    function assetPriceOracleAndSwapperStorage() internal pure returns (AssetPriceOracleAndSwapperStorage storage ds) {
        bytes32 position = ASSET_PRICE_ORACLE_AND_SWAPPER_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
