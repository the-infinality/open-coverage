// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapperEngine} from "../interfaces/ISwapperEngine.sol";
import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {Commands} from "@uniswap/universal-router/libraries/Commands.sol";
import {Constants} from "@uniswap/universal-router/libraries/Constants.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapV3SwapperEngineStorage {
    IUniversalRouter public universalRouter;
    IPermit2 public permit2;
    IQuoterV2 public quoterV2;
}

contract UniswapV3SwapperEngine is ISwapperEngine, UniswapV3SwapperEngineStorage {
    using SafeERC20 for IERC20;

    /// @notice Error thrown when the pool doesn't match expected base/swap tokens
    error PoolMismatch();

    /// @notice The address of this implementation contract, used to enforce delegatecall-only
    address private immutable SELF;

    /// @notice Ensures the function is only called via delegatecall
    modifier onlyDelegateCall() {
        _checkDelegateCall();
        _;
    }

    /// @notice Internal function to check if call is via delegatecall
    /// @dev Reverts if called directly (not via delegatecall)
    function _checkDelegateCall() internal view {
        if (address(this) == SELF) revert OnlyDelegateCall();
    }

    constructor(address _universalRouter, address _permit2, address _quoterV2) {
        SELF = address(this);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
        quoterV2 = IQuoterV2(_quoterV2);
    }

    /// @inheritdoc ISwapperEngine
    function name() external pure returns (string memory) {
        return "UniswapV3 Swapper Engine";
    }

    /// @inheritdoc ISwapperEngine
    function swapForInput(bytes memory poolInfo, uint256 amountIn, uint256 amountOutMin, address base, address swap)
        external
        onlyDelegateCall
        returns (uint256 amountOut)
    {
        // Extract first and last tokens from the path
        (address pathFirst, address pathLast) = _getAssetAddresses(poolInfo);

        // For EXACT_IN, path format is: input -> fee -> [intermediate -> fee ->]* output
        // So pathFirst should be the input token (base) and pathLast should be the output token (swap)
        address inputToken;
        address outputToken;
        bytes memory pathToUse;

        if (pathFirst == base && pathLast == swap) {
            // Path direction matches: pathFirst = input (base), pathLast = output (swap)
            inputToken = pathFirst;
            outputToken = pathLast;
            pathToUse = poolInfo;
        } else if (pathFirst == swap && pathLast == base) {
            // Path is reversed: pathFirst = output (swap), pathLast = input (base)
            // Reverse the path to match EXACT_IN format: input -> fee -> output
            inputToken = pathLast;
            outputToken = pathFirst;
            pathToUse = _reversePath(poolInfo);
        } else {
            // Pool doesn't match expected tokens
            revert PoolMismatch();
        }

        // Track output token balance before swap to calculate actual amount received
        uint256 balanceBefore = IERC20(outputToken).balanceOf(address(this));

        // Approve permit2 to spend input token
        // casting to 'uint160' is safe because token amounts are well below uint160 max value
        // forge-lint: disable-next-line(unsafe-typecast)
        _getPermit2().approve(inputToken, address(_getUniversalRouter()), uint160(amountIn), uint48(block.timestamp));

        // Build the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            address(this), // Recipient
            amountIn, // Amount in
            amountOutMin, // Amount out minimum
            pathToUse, // Path (may be reversed)
            true // Payer is user
        );

        // Execute the swap
        _getUniversalRouter().execute(commands, inputs, block.timestamp);

        // Calculate actual amount of output tokens received
        uint256 balanceAfter = IERC20(outputToken).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
    }

    /// @inheritdoc ISwapperEngine
    function swapForOutput(bytes memory poolInfo, uint256 amountOut, uint256 amountInMax, address base, address swap)
        external
        onlyDelegateCall
        returns (uint256 amountIn)
    {
        // Extract first and last tokens from the path
        (address pathFirst, address pathLast) = _getAssetAddresses(poolInfo);

        // For EXACT_OUT, path format is: output -> fee -> [intermediate -> fee ->]* input
        // So pathFirst should be the output token (swap) and pathLast should be the input token (base)
        address inputToken;
        bytes memory pathToUse;

        if (pathFirst == swap && pathLast == base) {
            // Path direction matches: pathFirst = output (swap), pathLast = input (base)
            inputToken = pathLast;
            pathToUse = poolInfo;
        } else if (pathFirst == base && pathLast == swap) {
            // Path is reversed: pathFirst = input (base), pathLast = output (swap)
            // Reverse the path to match EXACT_OUT format: output -> fee -> input
            inputToken = pathFirst;
            pathToUse = _reversePath(poolInfo);
        } else {
            // Pool doesn't match expected tokens
            revert PoolMismatch();
        }

        // Track input token balance before swap to calculate actual amount used
        uint256 balanceBefore = IERC20(inputToken).balanceOf(address(this));

        // Approve permit2 to spend input token
        // casting to 'uint160' is safe because token amounts are well below uint160 max value
        // forge-lint: disable-next-line(unsafe-typecast)
        _getPermit2().approve(inputToken, address(_getUniversalRouter()), uint160(amountInMax), uint48(block.timestamp));

        // Build the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_OUT));
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(
            address(this), // Recipient
            amountOut, // Amount out
            amountInMax, // Amount in maximum
            pathToUse, // Path (may be reversed)
            true // Payer is user
        );

        // Execute the swap
        _getUniversalRouter().execute(commands, inputs, block.timestamp);

        // Calculate actual amount of input tokens used
        uint256 balanceAfter = IERC20(inputToken).balanceOf(address(this));
        amountIn = balanceBefore - balanceAfter;
    }

    /// @inheritdoc ISwapperEngine
    function getQuote(bytes memory poolInfo, uint256 amountIn, address base, address quote)
        external
        returns (uint256 amountOut)
    {
        // Extract first and last tokens from the path
        (address pathFirst, address pathLast) = _getAssetAddresses(poolInfo);

        // For EXACT_IN quote, path format is: input -> fee -> [intermediate -> fee ->]* output
        // So pathFirst should be the input token (base) and pathLast should be the output token (quote)
        bytes memory pathToUse;

        if (pathFirst == base && pathLast == quote) {
            // Path direction matches: pathFirst = input (base), pathLast = output (quote)
            pathToUse = poolInfo;
        } else if (pathFirst == quote && pathLast == base) {
            // Path is reversed: pathFirst = output (quote), pathLast = input (base)
            // Reverse the path to match EXACT_IN format: input -> fee -> output
            pathToUse = _reversePath(poolInfo);
        } else {
            // Pool doesn't match expected tokens
            revert InvalidPoolInfo();
        }

        // Use QuoterV2 to get the quote
        // Note: quoteExactInput is not marked as view but can be called in view context
        // It uses staticcall internally and reverts to compute the result
        (amountOut,,,) = _getQuoterV2().quoteExactInput(pathToUse, amountIn);
    }

    function onInit(bytes memory poolInfo) external {
        (address assetA, address assetB) = _getAssetAddresses(poolInfo);
        if (assetA == address(0) || assetB == address(0)) revert InvalidPoolInfo();

        address permit2Address = address(_getPermit2());
        uint256 maxApproval = type(uint160).max;

        // Allow Permit2 to spend tokens - use forceApprove to handle USDT and other tokens
        // that revert when changing from non-zero to non-zero allowance
        IERC20(assetA).forceApprove(permit2Address, maxApproval);
        IERC20(assetB).forceApprove(permit2Address, maxApproval);
    }

    /// @notice Returns the asset addresses from the pool information
    /// @dev A good helper function for decoding the pool information
    /// @param poolInfo The pool information to use for the swap (can contain single or multiple pools)
    /// @return assetA The first asset in the pool info data
    /// @return assetB The last asset in the pool info data
    function getAssetAddresses(bytes memory poolInfo) external pure returns (address assetA, address assetB) {
        return _getAssetAddresses(poolInfo);
    }

    /// @notice Internal function to extract asset addresses from pool information
    /// @param poolInfo The pool information to use for the swap (can contain single or multiple pools)
    /// @return assetA The first asset in the pool info data
    /// @return assetB The last asset in the pool info data
    function _getAssetAddresses(bytes memory poolInfo) internal pure returns (address assetA, address assetB) {
        if (poolInfo.length < Constants.ADDR_SIZE) revert InvalidPoolInfo();

        // Extract first token (first 20 bytes)
        assembly {
            assetA := mload(add(poolInfo, 0x20)) // Skip length word, read first 20 bytes
            assetA := shr(96, assetA) // Right-align address (shift right by 96 bits)
        }

        // Extract last token (last 20 bytes)
        assembly {
            let len := mload(poolInfo) // Get length of poolInfo
            // Calculate offset to read last 32 bytes: start of data (0x20) + length - 32
            // If length < 32, we'll read from before the data start, but we handle this by reading from data start
            let dataStart := add(poolInfo, 0x20)
            let lastTokenOffset := add(dataStart, sub(len, 20)) // Offset to last 20 bytes
            let lastWord := mload(lastTokenOffset) // Read 32 bytes starting from last token position
            assetB := shr(96, lastWord) // Right-align address (shift right by 96 bits)
        }
    }

    /// @notice Reverses a Uniswap V3 path
    /// @dev Path format: token0 (20 bytes) + fee0 (3 bytes) + token1 (20 bytes) + fee1 (3 bytes) + ... + tokenN (20 bytes)
    /// @dev Reversed format: tokenN (20 bytes) + feeN-1 (3 bytes) + tokenN-1 (20 bytes) + feeN-2 (3 bytes) + ... + token0 (20 bytes)
    /// @param poolInfo The original path to reverse
    /// @return reversedPath The reversed path
    function _reversePath(bytes memory poolInfo) internal pure returns (bytes memory reversedPath) {
        uint256 len = poolInfo.length;
        require(len >= Constants.ADDR_SIZE, "PoolInfo too short");

        // Single pool case: path is just one token (20 bytes), so reversed is the same
        if (len == 20) {
            reversedPath = new bytes(20);
            // Copy all 20 bytes
            for (uint256 i = 0; i < 20; i++) {
                reversedPath[i] = poolInfo[i];
            }
        } else {
            // Allocate memory for reversed path (same length)
            reversedPath = new bytes(len);

            // Calculate number of pools: (len - 20) / 23 + 1
            // Each intermediate pool adds 23 bytes (token + fee), last pool is just token (20 bytes)
            uint256 numPools = (len - 20) / 23 + 1;

            // Copy last token to first position (20 bytes)
            for (uint256 i = 0; i < 20; i++) {
                reversedPath[i] = poolInfo[len - 20 + i];
            }

            // Process intermediate pools: copy fees and tokens in reverse order
            uint256 dstOffset = 20; // Write position starts after first token
            uint256 srcOffset = len - 23; // Start reading from second-to-last fee

            // For each intermediate pool (from pool N-1 down to pool 1)
            for (uint256 i = 1; i < numPools; i++) {
                // Copy fee (3 bytes) from source to destination
                for (uint256 j = 0; j < 3; j++) {
                    reversedPath[dstOffset + j] = poolInfo[srcOffset + j];
                }

                // Move source offset back 20 bytes to read token
                // Use unchecked since we know srcOffset >= 20 at this point
                unchecked {
                    srcOffset -= 20;
                }

                // Copy token (20 bytes) from source to destination byte-by-byte
                for (uint256 k = 0; k < 20; k++) {
                    reversedPath[dstOffset + 3 + k] = poolInfo[srcOffset + k];
                }

                // Update offsets for next iteration
                dstOffset += 23; // Move past fee (3) + token (20)

                // Only move srcOffset back if there are more pools to process
                if (i + 1 < numPools) {
                    unchecked {
                        srcOffset -= 3; // Move back 3 bytes to next fee position
                    }
                }
            }

            // Copy first token to last position (20 bytes)
            for (uint256 i = 0; i < 20; i++) {
                reversedPath[len - 20 + i] = poolInfo[i];
            }
        }
    }

    function _getPermit2() private view returns (IPermit2) {
        return UniswapV3SwapperEngineStorage(SELF).permit2();
    }

    function _getQuoterV2() private view returns (IQuoterV2) {
        return UniswapV3SwapperEngineStorage(SELF).quoterV2();
    }

    function _getUniversalRouter() private view returns (IUniversalRouter) {
        return UniswapV3SwapperEngineStorage(SELF).universalRouter();
    }
}
