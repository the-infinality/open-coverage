// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapper} from "../../src/mixins/AssetPriceOracleAndSwapper.sol";
import {AssetPair} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title MockAssetPriceOracleAndSwapper
/// @notice Mock implementation of AssetPriceOracleAndSwapper with owner check
/// @dev Used for testing purposes
contract MockAssetPriceOracleAndSwapper is AssetPriceOracleAndSwapper {
    address public owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_) {
        owner = owner_;
        // Initialize default swap slippage (1%)
        _initializeSwapSlippage();
    }

    /// @notice Override register to add owner check
    /// @param _assetPair The asset pair configuration
    function register(AssetPair calldata _assetPair) public override onlyOwner {
        super.register(_assetPair);
    }
}

