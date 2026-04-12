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
    /// @notice Internal registration of an asset pair (delegatecall to swap engine onInit).
    /// @dev Made internal to avoid controlled-delegatecall from untrusted callers; only facet/exposed entrypoints should call this after access control.
    /// @param _assetPair The asset pair configuration
    // slither-disable-next-line reentrancy-events -- delegatecall same storage context; event after call is benign
    function _register(AssetPair calldata _assetPair) internal {
        bool priceOracleRequired = _assetPair.priceStrategy != PriceStrategy.SwapperOnly;
        if (_assetPair.priceOracle == address(0) && priceOracleRequired) revert PriceOracleRequired();
        if (priceOracleRequired && _assetPair.swapperAccuracy == 0) revert InvalidSwapperAccuracy();

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
        // slither-disable-next-line controlled-delegatecall -- only callable via an external function which should enforce contract ownership
        (bool success,) = _assetPair.swapEngine
            .delegatecall(abi.encodeWithSelector(ISwapperEngine.onInit.selector, _assetPair.poolInfo));

        if (!success) revert InvalidPoolInfo();

        emit AssetPairRegistered(_assetPair.assetA, _assetPair.assetB);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForOutput(uint256 amountOut, address base, address swap, uint256 deadline) public {
        AssetPair memory _assetPair = _getRegisteredAssetPair(base, swap);
        require(
            deadline <= _maxDeadlineOffset() + block.timestamp,
            ExceedsMaxDeadline(_maxDeadlineOffset() + block.timestamp, deadline)
        );

        (uint256 maxAmountIn,) = swapForOutputQuote(amountOut, base, swap);

        // Delegatecall version of swapForOutput
        (bool success,) = _assetPair.swapEngine
            .delegatecall(
                abi.encodeWithSignature(
                    "swapForOutput(bytes,uint256,uint256,address,address,uint256)",
                    _assetPair.poolInfo,
                    amountOut,
                    maxAmountIn,
                    base,
                    swap,
                    deadline
                )
            );
        if (!success) revert SwapFailed();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForInput(uint256 amountIn, address base, address swap, uint256 deadline) public {
        AssetPair memory _assetPair = _getRegisteredAssetPair(base, swap);
        require(
            deadline <= _maxDeadlineOffset() + block.timestamp,
            ExceedsMaxDeadline(_maxDeadlineOffset() + block.timestamp, deadline)
        );

        (uint256 minAmountOut,) = swapForInputQuote(amountIn, base, swap);

        // Delegatecall version of swapForInput
        (bool success,) = _assetPair.swapEngine
            .delegatecall(
                abi.encodeWithSignature(
                    "swapForInput(bytes,uint256,uint256,address,address,uint256)",
                    _assetPair.poolInfo,
                    amountIn,
                    minAmountOut,
                    base,
                    swap,
                    deadline
                )
            );
        if (!success) revert SwapFailed();
    }

    /// @notice Sets the swap slippage in basis points (0-10000). Internal; expose via facet with access control.
    /// @param swapSlippage_ The swap slippage in basis points
    function _setSwapSlippageChecked(uint16 swapSlippage_) internal {
        if (swapSlippage_ > 10000) revert InvalidSwapSlippage();
        _setSwapSlippage(swapSlippage_);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapSlippage() external view returns (uint16) {
        return _swapSlippage();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function maxDeadlineOffset() external view returns (uint256) {
        return _maxDeadlineOffset();
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function assetPair(address assetA, address assetB) public view returns (AssetPair memory) {
        return _getRegisteredAssetPair(assetA, assetB);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function getQuote(uint256 inAmount, address base, address quote)
        public
        view
        returns (uint256 outAmount, bool verified)
    {
        AssetPair memory _assetPair = _getRegisteredAssetPair(base, quote);
        verified = true;

        if (_assetPair.priceStrategy == PriceStrategy.OracleOnly) {
            outAmount = IPriceOracle(_assetPair.priceOracle).getQuote(inAmount, base, quote);
        } else if (_assetPair.priceStrategy == PriceStrategy.SwapperOnly) {
            outAmount = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, inAmount, base, quote);
        } else {
            uint256 verifyingQuote = 0;
            if (_assetPair.priceStrategy == PriceStrategy.SwapperVerified) {
                outAmount = ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, inAmount, base, quote);
                verifyingQuote = IPriceOracle(_assetPair.priceOracle).getQuote(inAmount, base, quote);
            } else if (_assetPair.priceStrategy == PriceStrategy.OracleVerified) {
                outAmount = IPriceOracle(_assetPair.priceOracle).getQuote(inAmount, base, quote);
                verifyingQuote =
                    ISwapperEngine(_assetPair.swapEngine).getQuote(_assetPair.poolInfo, inAmount, base, quote);
            }
            uint256 diff = outAmount > verifyingQuote ? outAmount - verifyingQuote : verifyingQuote - outAmount;
            uint256 tolerance = (outAmount * _assetPair.swapperAccuracy) / 10000;
            verified = diff <= tolerance;
        }
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForOutputQuote(uint256 amountOut, address base, address swap)
        public
        view
        returns (uint256 maxAmountIn, bool verified)
    {
        // getQuote(inAmount, base, quote) returns outAmount of quote for inAmount of base.
        // We need maxAmountIn of swap for amountOut of base → getQuote(amountOut, swap, base).
        (uint256 q, bool verified_) = getQuote(amountOut, swap, base);
        maxAmountIn = q + (uint256(_swapSlippage()) * q) / 10000;
        verified = verified_;
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swapForInputQuote(uint256 amountIn, address base, address swap)
        public
        view
        returns (uint256 minAmountOut, bool verified)
    {
        (uint256 q, bool verified_) = getQuote(amountIn, base, swap);
        minAmountOut = q - (q * uint256(_swapSlippage())) / 10000;
        verified = verified_;
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
