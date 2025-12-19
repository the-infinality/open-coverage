// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

interface IPriceOracle {
    /// @return General description of this oracle implementation.
    function name() external view returns (string memory);

    /// @return outAmount The amount of `quote` that is equivalent to `inAmount` of `base`.
    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256 outAmount);

    /// @return bidOutAmount The amount of `quote` you would get for selling `inAmount` of `base`.
    /// @return askOutAmount The amount of `quote` you would spend for buying `inAmount` of `base`.
    function getQuotes(uint256 inAmount, address base, address quote)
        external
        view
        returns (uint256 bidOutAmount, uint256 askOutAmount);
}

enum SwapEngine {
    UNISWAP_V3,
    UNISWAP_V4_SINGLE_HOP
}

struct SwapParams {
    SwapEngine swapEngine;
    bytes poolInfo;
}

struct UniswapV4PoolInfo {
    PoolKey poolKey;
    bool zeroForOne;
}

struct AssetPair {
    /// @notice The price oracle implementing the IPriceOracle
    address priceOracle;

    /// @notice The asset used to swap from
    address asset1;

    /// @notice The asset used to swap to
    address asset2;

    /// @notice The pool path to use for swapping via a configured SwapEngine
    SwapParams swapParams;
}

abstract contract AssetPriceOracleAndSwapper {
    error InvalidSwapEngine();
    error AssetPairNotRegistered();
    error InvalidPriceOracle();
    error InvalidAssetPair();
    error SliceOutOfBounds();

    IUniversalRouter public universalRouter;
    IPermit2 public permit2;

    mapping(bytes32 => AssetPair) public assetPairs;

    constructor() {}

    function __AssetPriceOracleAndSwapper_init(address universalRouter_, address permit2_) public virtual {
        universalRouter = IUniversalRouter(universalRouter_);
        permit2 = IPermit2(permit2_);
    }

    function registerPriceAdaptor(address priceOracle, address asset1, address asset2, SwapParams calldata swapParams)
        external
    {
        if (priceOracle == address(0)) revert InvalidPriceOracle();
        if (asset1 == address(0) || asset2 == address(0)) revert InvalidAssetPair();

        AssetPair memory _assetPair =
            AssetPair({priceOracle: priceOracle, asset1: asset1, asset2: asset2, swapParams: swapParams});

        assetPairs[keccak256(abi.encode(asset1, asset2))] = _assetPair;

        // Allow Permit2 to spend asset 1
        IERC20(asset1).approve(address(permit2), type(uint256).max);
        // TODO: Validate that the pool path is valid
    }

    /// =========== Swap Functions ===========

    function swap(uint128 amountOut, address asset1, address asset2) public {
        AssetPair memory _assetPair = assetPairs[keccak256(abi.encode(asset1, asset2))];

        if (address(_assetPair.priceOracle) == address(0)) revert AssetPairNotRegistered();

        if (_assetPair.swapParams.swapEngine == SwapEngine.UNISWAP_V3) {
            _swapV3(amountOut, _assetPair.swapParams.poolInfo);
        } else if (_assetPair.swapParams.swapEngine == SwapEngine.UNISWAP_V4_SINGLE_HOP) {
            _swapV4SingleHop(amountOut, _assetPair.swapParams.poolInfo);
        } else {
            revert InvalidSwapEngine();
        }
    }

    function _swapV3(uint128 amountOut, bytes memory poolInfo) internal {
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

        permit2.approve(inputToken, address(universalRouter), type(uint160).max, uint48(block.timestamp));

        inputs[0] = abi.encode(
            address(this), // Recipient
            amountOut, // Amount out
            type(uint256).max, // Amount in maximum
            poolInfo, // Path
            true // Payer is user
        );
        universalRouter.execute(commands, inputs, block.timestamp);
    }

    function _swapV4SingleHop(uint128 amountOut, bytes memory poolInfo) internal {
        UniswapV4PoolInfo memory uniswapV4PoolInfo = abi.decode(poolInfo, (UniswapV4PoolInfo));

        // Approve the universal router to spend currency0 (input token)
        address inputToken = Currency.unwrap(uniswapV4PoolInfo.poolKey.currency0);
        permit2.approve(inputToken, address(universalRouter), type(uint160).max, uint48(block.timestamp));

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

        universalRouter.execute(commands, inputs, block.timestamp);
    }

    /// =========== Discovery Functions ===========

    /// @notice Get the asset pair for two assets
    /// @param asset1 The first asset
    /// @param asset2 The second asset
    /// @return The asset pair for the two assets
    function assetPair(address asset1, address asset2) public view returns (AssetPair memory) {
        return assetPairs[keccak256(abi.encode(asset1, asset2))];
    }

    /// @notice Get the price quote of one asset in terms of another
    /// @param amountIn The amount of the first asset to get price for second asset
    /// @param asset1 The first asset
    /// @param asset2 The second asset
    /// @return The price of the first asset in terms of the second asset
    function quote(uint256 amountIn, address asset1, address asset2) public view returns (uint256) {
        AssetPair memory _assetPair = assetPairs[keccak256(abi.encode(asset1, asset2))];

        // Should flip around since the price oracle works both ways
        if (address(_assetPair.priceOracle) == address(0)) {
            _assetPair = assetPairs[keccak256(abi.encode(asset2, asset1))];
            if (address(_assetPair.priceOracle) == address(0)) {
                revert AssetPairNotRegistered();
            }
        }
        return IPriceOracle(_assetPair.priceOracle).getQuote(amountIn, asset1, asset2);
    }
}
