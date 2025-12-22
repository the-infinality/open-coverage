// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperStorage
/// @author p-dealwis, Infinality
/// @notice Diamond storage for the AssetPriceOracleAndSwapper facet
/// @dev Uses EIP-2535 diamond storage pattern
abstract contract AssetPriceOracleAndSwapperStorage {
    /// @notice Mapping from asset pair hash to asset pair configuration
    mapping(bytes32 => AssetPair) assetPairs;

    /// @notice The swap slippage in basis points i.e. 1 = 0.01%
    /// @dev Default slippage set to 1%
    uint16 internal _swapSlippage = 100;
}

