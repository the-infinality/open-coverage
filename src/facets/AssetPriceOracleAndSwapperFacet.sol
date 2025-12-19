// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapper} from "../mixins/AssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperFacet
/// @author p-dealwis, Infinality
/// @notice Diamond facet for managing asset price oracles and executing swaps
/// @dev This contract is designed to be called via delegatecall from a Diamond proxy
contract AssetPriceOracleAndSwapperFacet is AssetPriceOracleAndSwapper {
    // All functionality is inherited from AssetPriceOracleAndSwapper
    // This facet exposes the abstract contract's functions through the diamond pattern
}

