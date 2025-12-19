// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperStorage
/// @author p-dealwis, Infinality
/// @notice Diamond storage for the AssetPriceOracleAndSwapper facet
/// @dev Uses EIP-2535 diamond storage pattern with a unique storage slot
abstract contract AssetPriceOracleAndSwapperStorage {
    /// @notice Storage struct for asset price oracle and swapper data
    struct SwapperStorage {
        /// @notice The Uniswap Universal Router for executing swaps
        IUniversalRouter universalRouter;
        /// @notice The Permit2 contract for token approvals
        IPermit2 permit2;
        /// @notice Mapping of asset pair keys to their configurations
        mapping(bytes32 => AssetPair) assetPairs;
    }

    /// @notice Storage slot for the swapper storage (keccak256("open-coverage.storage.AssetPriceOracleAndSwapper") - 1)
    bytes32 private constant SWAPPER_STORAGE_SLOT =
        0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19a;

    /// @notice Returns the swapper storage struct from the designated storage slot
    function _swapperStorage() internal pure returns (SwapperStorage storage s) {
        bytes32 slot = SWAPPER_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}

