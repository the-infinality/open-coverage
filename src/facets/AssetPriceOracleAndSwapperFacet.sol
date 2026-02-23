// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapper} from "../mixins/AssetPriceOracleAndSwapper.sol";
import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {AssetPair} from "../interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperFacet
/// @author p-dealwis, Infinality
/// @notice Diamond facet for managing asset price oracles and executing swaps
/// @dev This contract is designed to be called via delegatecall from a Diamond proxy
contract AssetPriceOracleAndSwapperFacet is AssetPriceOracleAndSwapper {
    // All functionality is inherited from AssetPriceOracleAndSwapper
    // This facet exposes the abstract contract's functions through the diamond pattern

    /// @notice Registers a price adaptor for an asset pair (owner only).
    /// @param _assetPair The asset pair configuration
    function register(AssetPair calldata _assetPair) external {
        LibDiamond.enforceIsContractOwner();
        _register(_assetPair);
    }

    /// @notice Sets the swap slippage (owner only).
    /// @param swapSlippage_ The swap slippage in basis points (0-10000)
    function setSwapSlippage(uint16 swapSlippage_) external {
        LibDiamond.enforceIsContractOwner();
        _setSwapSlippageChecked(swapSlippage_);
    }
}
