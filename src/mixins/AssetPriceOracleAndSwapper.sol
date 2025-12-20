// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

import {AssetPriceOracleAndSwapperStorage} from "../storage/AssetPriceOracleAndSwapperStorage.sol";
import {
    IAssetPriceOracleAndSwapper,
    SwapEngine,
    SwapParams,
    UniswapV4PoolInfo,
    AssetPair
} from "../interfaces/IAssetPriceOracleAndSwapper.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title AssetPriceOracleAndSwapper
/// @author p-dealwis, Infinality
/// @notice Abstract contract for managing asset price oracles and executing swaps
/// @dev Extend this contract to add price oracle and swap functionality to your diamond facets
abstract contract AssetPriceOracleAndSwapper is AssetPriceOracleAndSwapperStorage, IAssetPriceOracleAndSwapper {
    /// @notice Initializes the swapper with universal router and permit2 addresses
    /// @param universalRouter_ The Uniswap Universal Router address
    /// @param permit2_ The Permit2 contract address
    function __AssetPriceOracleAndSwapper_init(address universalRouter_, address permit2_) internal {
        SwapperStorage storage s = _swapperStorage();
        s.universalRouter = IUniversalRouter(universalRouter_);
        s.permit2 = IPermit2(permit2_);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function registerPriceAdaptor(address priceOracle, address asset1, address asset2, SwapParams calldata swapParams)
        external
        virtual
    {
        if (priceOracle == address(0)) revert InvalidPriceOracle();
        if (asset1 == address(0) || asset2 == address(0)) revert InvalidAssetPair();

        AssetPair memory _assetPair =
            AssetPair({priceOracle: priceOracle, asset1: asset1, asset2: asset2, swapParams: swapParams});

        SwapperStorage storage s = _swapperStorage();
        s.assetPairs[keccak256(abi.encode(asset1, asset2))] = _assetPair;

        // Allow Permit2 to spend asset 1
        IERC20(asset1).approve(address(s.permit2), type(uint256).max);
        // TODO: Validate that the pool path is valid
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function swap(uint128 amountOut, address asset1, address asset2) public virtual {
        SwapperStorage storage s = _swapperStorage();
        AssetPair memory _assetPair = s.assetPairs[keccak256(abi.encode(asset1, asset2))];

        if (address(_assetPair.priceOracle) == address(0)) revert AssetPairNotRegistered();

        if (_assetPair.swapParams.swapEngine == SwapEngine.UNISWAP_V3) {
            _swapV3(amountOut, _assetPair.swapParams.poolInfo);
        } else if (_assetPair.swapParams.swapEngine == SwapEngine.UNISWAP_V4_SINGLE_HOP) {
            _swapV4SingleHop(amountOut, _assetPair.swapParams.poolInfo);
        } else {
            revert InvalidSwapEngine();
        }
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function assetPair(address asset1, address asset2) public view virtual returns (AssetPair memory) {
        return _swapperStorage().assetPairs[keccak256(abi.encode(asset1, asset2))];
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function quote(uint256 amountIn, address asset1, address asset2) public view virtual returns (uint256) {
        SwapperStorage storage s = _swapperStorage();
        AssetPair memory _assetPair = s.assetPairs[keccak256(abi.encode(asset1, asset2))];

        // Should flip around since the price oracle works both ways
        if (address(_assetPair.priceOracle) == address(0)) {
            _assetPair = s.assetPairs[keccak256(abi.encode(asset2, asset1))];
            if (address(_assetPair.priceOracle) == address(0)) {
                revert AssetPairNotRegistered();
            }
        }
        return IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, asset1, asset2);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function universalRouter() public view virtual returns (address) {
        return address(_swapperStorage().universalRouter);
    }

    /// @inheritdoc IAssetPriceOracleAndSwapper
    function permit2() public view virtual returns (address) {
        return address(_swapperStorage().permit2);
    }

    // ============ Internal Functions ============ //

    function _swapV3(uint128 amountOut, bytes memory poolInfo) internal {
        SwapperStorage storage s = _swapperStorage();

        bytes[] memory inputs = new bytes[](1);
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_OUT));

        // Extract input token from V3 poolInfo path (last 20 bytes of the path)
        // For EXACT_OUT, path format is: output -> fee -> [intermediate -> fee ->]* input
        // The input token is always the last 20 bytes
        address inputToken;
        assembly {
            let len := mload(poolInfo) // Get length of poolInfo
            inputToken := mload(add(poolInfo, len)) // Input token ends at offset len, mload reads 32 bytes so address is right-aligned
        }

        s.permit2.approve(inputToken, address(s.universalRouter), type(uint160).max, uint48(block.timestamp));

        inputs[0] = abi.encode(
            address(this), // Recipient
            amountOut, // Amount out
            type(uint256).max, // Amount in maximum
            poolInfo, // Path
            true // Payer is user
        );
        s.universalRouter.execute(commands, inputs, block.timestamp);
    }

    function _swapV4SingleHop(uint128 amountOut, bytes memory poolInfo) internal {
        SwapperStorage storage s = _swapperStorage();

        UniswapV4PoolInfo memory uniswapV4PoolInfo = abi.decode(poolInfo, (UniswapV4PoolInfo));

        // Approve the universal router to spend currency0 (input token)
        address inputToken = Currency.unwrap(uniswapV4PoolInfo.poolKey.currency0);
        s.permit2.approve(inputToken, address(s.universalRouter), type(uint160).max, uint48(block.timestamp));

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: uniswapV4PoolInfo.poolKey,
                zeroForOne: uniswapV4PoolInfo.zeroForOne, // true if we're swapping token0 for token1
                amountOut: amountOut, // amount of tokens we're swapping
                amountInMaximum: type(uint128).max, // minimum amount we expect to receive
                hookData: bytes("") // no hook data needed
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(uniswapV4PoolInfo.poolKey.currency0, type(uint128).max);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(uniswapV4PoolInfo.poolKey.currency1, amountOut);

        // Consolidate the inputs into a single bytes array
        inputs[0] = abi.encode(actions, params);

        s.universalRouter.execute(commands, inputs, block.timestamp);
    }
}

