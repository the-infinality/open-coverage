// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapperStorage} from "../storage/AssetPriceOracleAndSwapperStorage.sol";
import {IAssetPriceOracleAndSwapper, AssetPair, PriceStrategy} from "../interfaces/IAssetPriceOracleAndSwapper.sol";
import {ISwapperEngine} from "../interfaces/ISwapperEngine.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title AssetPriceOracleAndSwapper
/// @author p-dealwis, Infinality
/// @notice Abstract contract for managing asset price oracles and executing swaps
abstract contract AssetPriceOracleAndSwapper is AssetPriceOracleAndSwapperStorage, IAssetPriceOracleAndSwapper {
    /// @inheritdoc IAssetPriceOracleAndSwapper
    function register(AssetPair calldata _assetPair) external virtual {
        bool priceOracleRequired =
            _assetPair.priceStrategy != PriceStrategy.SwapperOnly || _assetPair.swapperAccuracy != 0;
        if (_assetPair.priceOracle == address(0) && priceOracleRequired) revert PriceOracleRequired();

        if (_assetPair.assetA == address(0) || _assetPair.assetB == address(0)) revert InvalidAssetPair();

        assetPairs[keccak256(abi.encode(_assetPair.assetA, _assetPair.assetB))] = _assetPair;

        // delegatecall to onInit instead of direct call
        (bool success,) = _assetPair.swapEngine
            .delegatecall(abi.encodeWithSelector(ISwapperEngine.onInit.selector, _assetPair.poolInfo));

        if (!success) revert InvalidPoolInfo();

        emit AssetPairRegistered(_assetPair.assetA, _assetPair.assetB);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForOutput(uint128 amountOut, address assetA, address assetB) public virtual {
        AssetPair memory _assetPair = assetPairs[keccak256(abi.encode(assetA, assetB))];

        if (address(_assetPair.swapEngine) == address(0)) revert AssetPairNotRegistered();

        // Delegatecall version of swapForOutput
        (bool success,) = _assetPair.swapEngine
            .delegatecall(
                abi.encodeWithSignature(
                    "swapForOutput(bytes,uint256,uint256,address,address)",
                    _assetPair.poolInfo,
                    amountOut,
                    type(uint256).max,
                    assetA,
                    assetB
                )
            );
        if (!success) revert SwapFailed();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForInput(uint128 amountIn, address assetA, address assetB) public virtual {
        AssetPair memory _assetPair = assetPairs[keccak256(abi.encode(assetA, assetB))];

        if (address(_assetPair.swapEngine) == address(0)) revert AssetPairNotRegistered();

        // Delegatecall version of swapForInput
        (bool success,) = _assetPair.swapEngine
            .delegatecall(
                abi.encodeWithSignature(
                    "swapForInput(bytes,uint256,uint256,address,address)",
                    _assetPair.poolInfo,
                    amountIn,
                    type(uint256).max,
                    assetA,
                    assetB
                )
            );
        if (!success) revert SwapFailed();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function assetPair(address assetA, address assetB) public view virtual returns (AssetPair memory) {
        return assetPairs[keccak256(abi.encode(assetA, assetB))];
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function getQuote(uint256 amountIn, address assetA, address assetB) public view virtual returns (uint256) {
        AssetPair memory _assetPair = assetPairs[keccak256(abi.encode(assetA, assetB))];

        // Should flip around since the price oracle works both ways
        if (address(_assetPair.priceOracle) == address(0)) {
            _assetPair = assetPairs[keccak256(abi.encode(assetB, assetA))];
            if (address(_assetPair.priceOracle) == address(0)) {
                revert AssetPairNotRegistered();
            }
        }
        return IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, assetA, assetB);
    }
}

