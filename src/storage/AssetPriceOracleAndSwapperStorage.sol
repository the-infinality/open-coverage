// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperStorage
/// @author p-dealwis, Infinality
/// @notice Diamond storage for the AssetPriceOracleAndSwapper facet
/// @dev Uses EIP-2535 diamond storage pattern
abstract contract AssetPriceOracleAndSwapperStorage {
    mapping(bytes32 => AssetPair) assetPairs;
}

