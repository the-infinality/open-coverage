// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapperStorage} from "../storage/AssetPriceOracleAndSwapperStorage.sol";
import {IAssetPriceOracleAndSwapper, AssetPair, PriceStrategy} from "../interfaces/IAssetPriceOracleAndSwapper.sol";
import {ISwapperEngine} from "../interfaces/ISwapperEngine.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title AssetPriceOracleAndSwapper
/// @author p-dealwis, Infinality
/// @notice Mixin contract for quoting and swapping assets
/// @dev This contract utlised Swapper Engines with optional price oracles
abstract contract AssetPriceOracleAndSwapper is AssetPriceOracleAndSwapperStorage, IAssetPriceOracleAndSwapper {
    /// @inheritdoc IAssetPriceOracleAndSwapper
    function register(AssetPair calldata _assetPair) public virtual {
        bool priceOracleRequired =
            _assetPair.priceStrategy != PriceStrategy.SwapperOnly || _assetPair.swapperAccuracy != 0;
        if (_assetPair.priceOracle == address(0) && priceOracleRequired) revert PriceOracleRequired();

        if (_assetPair.assetA == address(0) || _assetPair.assetB == address(0)) revert InvalidAssetPair();

        AssetPair storage storedPair = assetPairs(keccak256(abi.encode(_assetPair.assetA, _assetPair.assetB)));
        storedPair.assetA = _assetPair.assetA;
        storedPair.assetB = _assetPair.assetB;
        storedPair.swapEngine = _assetPair.swapEngine;
        storedPair.poolInfo = _assetPair.poolInfo;
        storedPair.priceStrategy = _assetPair.priceStrategy;
        storedPair.swapperAccuracy = _assetPair.swapperAccuracy;
        storedPair.priceOracle = _assetPair.priceOracle;

        // delegatecall to onInit instead of direct call
        (bool success,) = _assetPair.swapEngine.delegatecall(
            abi.encodeWithSelector(ISwapperEngine.onInit.selector, _assetPair.poolInfo)
        );

        if (!success) revert InvalidPoolInfo();

        emit AssetPairRegistered(_assetPair.assetA, _assetPair.assetB);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForOutput(uint256 amountOut, address assetA, address assetB) public {
        AssetPair memory _assetPair = _getRegisteredAssetPair(assetA, assetB);

        uint256 maxAmountIn = swapForOutputQuote(amountOut, assetB, assetA);

        // Delegatecall version of swapForOutput
        (bool success,) = _assetPair.swapEngine.delegatecall(
            abi.encodeWithSignature(
                "swapForOutput(bytes,uint256,uint256,address,address)",
                _assetPair.poolInfo,
                amountOut,
                maxAmountIn,
                assetA,
                assetB
            )
        );
        if (!success) revert SwapFailed();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForInput(uint256 amountIn, address assetA, address assetB) public {
        AssetPair memory _assetPair = _getRegisteredAssetPair(assetA, assetB);

        uint256 minAmountOut = swapForInputQuote(amountIn, assetB, assetA);

        // Delegatecall version of swapForInput
        (bool success,) = _assetPair.swapEngine.delegatecall(
            abi.encodeWithSignature(
                "swapForInput(bytes,uint256,uint256,address,address)",
                _assetPair.poolInfo,
                amountIn,
                minAmountOut,
                assetA,
                assetB
            )
        );
        if (!success) revert SwapFailed();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function setSwapSlippage(uint16 swapSlippage_) public virtual {
        if (swapSlippage_ > 10000) revert InvalidSwapSlippage();
        _setSwapSlippage(swapSlippage_);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapSlippage() external view returns (uint16) {
        return _swapSlippage();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function assetPair(address assetA, address assetB) public view returns (AssetPair memory) {
        return assetPairs(keccak256(abi.encode(assetA, assetB)));
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function getQuote(uint256 amountIn, address assetA, address assetB)
        external
        view
        returns (uint256 quote, bool verified)
    {
        AssetPair memory _assetPair = _getRegisteredAssetPair(assetA, assetB);
        verified = true;

        if (_assetPair.priceStrategy == PriceStrategy.OracleOnly) {
            quote = IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, assetA, assetB);
        } else if (_assetPair.priceStrategy == PriceStrategy.SwapperOnly) {
            quote = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
        } else {
            uint256 verifyingQuote = 0;
            if (_assetPair.priceStrategy == PriceStrategy.SwapperVerified) {
                quote = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
                verifyingQuote = IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, assetA, assetB);
            } else if (_assetPair.priceStrategy == PriceStrategy.OracleVerified) {
                quote = IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, assetA, assetB);
                verifyingQuote =
                    ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
            }
            uint256 diff = quote > verifyingQuote ? quote - verifyingQuote : verifyingQuote - quote;
            uint256 tolerance = (quote * _assetPair.swapperAccuracy) / 10000;
            verified = diff <= tolerance;
        }
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForOutputQuote(uint256 amountOut, address assetA, address assetB)
        public
        view
        returns (uint256 maxAmountIn)
    {
        AssetPair memory _assetPair = _getRegisteredAssetPair(assetA, assetB);
        maxAmountIn = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountOut, assetA, assetB);
        maxAmountIn = maxAmountIn + (uint256(_swapSlippage()) * maxAmountIn) / 10000;
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForInputQuote(uint256 amountIn, address assetA, address assetB)
        public
        view
        returns (uint256 minAmountOut)
    {
        AssetPair memory _assetPair = _getRegisteredAssetPair(assetA, assetB);
        minAmountOut = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, amountIn, assetA, assetB);
        minAmountOut = minAmountOut - (minAmountOut * uint256(_swapSlippage())) / 10000;
    }

    /// @notice Gets the registered asset pair and reverts if not registered
    /// @param assetA The first asset
    /// @param assetB The second asset
    /// @return _assetPair The registered asset pair
    function _getRegisteredAssetPair(address assetA, address assetB)
        private
        view
        returns (AssetPair memory _assetPair)
    {
        _assetPair = assetPairs(keccak256(abi.encode(assetA, assetB)));
        // Should flip around since the price oracle works both ways
        if (address(_assetPair.swapEngine) == address(0)) {
            _assetPair = assetPairs(keccak256(abi.encode(assetB, assetA)));
            if (address(_assetPair.swapEngine) == address(0)) {
                revert AssetPairNotRegistered();
            }
        }
    }
}
