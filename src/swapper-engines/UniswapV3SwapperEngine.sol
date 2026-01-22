// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {Commands} from "@uniswap/universal-router/libraries/Commands.sol";
import {Constants} from "@uniswap/universal-router/libraries/Constants.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IQuoter} from "src/interfaces/IQuoter.sol";

contract UniswapV3SwapperEngineStorage {
    IUniversalRouter public universalRouter;
    IPermit2 public permit2;
    IQuoter public quoter;
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

    constructor(address _universalRouter, address _permit2, address _quoter) {
        SELF = address(this);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
        quoter = IQuoter(_quoter);
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
        // So pathFirst should be the input token (swap) and pathLast should be the output token (base)
        address inputToken;
        address outputToken;
        bytes memory pathToUse;

        if (pathFirst == swap && pathLast == base) {
            // Path direction matches: pathFirst = input (swap), pathLast = output (base)
            inputToken = pathFirst;
            outputToken = pathLast;
            pathToUse = poolInfo;
        } else if (pathFirst == base && pathLast == swap) {
            // Path is reversed: pathFirst = output (base), pathLast = input (swap)
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
        // So pathFirst should be the output token (base) and pathLast should be the input token (swap)
        address inputToken;
        bytes memory pathToUse;

        if (pathFirst == base && pathLast == swap) {
            // Path direction matches: pathFirst = output (base), pathLast = input (swap)
            inputToken = pathLast;
            pathToUse = poolInfo;
        } else if (pathFirst == swap && pathLast == base) {
            // Path is reversed: pathFirst = input (swap), pathLast = output (base)
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
        view
        returns (uint256 amountOut)
    {
        // Extract first and last tokens from the path
        (address pathFirst, address pathLast) = _getAssetAddresses(poolInfo);

        // For EXACT_IN quote, path format is: input -> fee -> [intermediate -> fee ->]* output
        // So pathFirst should be the input token (quote) and pathLast should be the output token (base)
        // We want to know: given amountIn of quote, how much base do we get?
        bytes memory pathToUse;

        if (pathFirst == quote && pathLast == base) {
            // Path direction matches: pathFirst = input (quote), pathLast = output (base)
            pathToUse = poolInfo;
        } else if (pathFirst == base && pathLast == quote) {
            // Path is reversed: pathFirst = output (base), pathLast = input (quote)
            // Reverse the path to match EXACT_IN format: input -> fee -> output
            pathToUse = _reversePath(poolInfo);
        } else {
            // Pool doesn't match expected tokens
            revert InvalidPoolInfo();
        }

        // To avoid large swap discrepancies and gas/timeout issues, calculate exchange rate first
        // Quote with 1 unit (based on token decimals) to get the exchange rate, then multiply by amountIn
        // This is more gas-efficient and avoids precision issues with very large amounts

        // Get the decimals of the quote token to determine the unit amount
        uint8 quoteDecimals = 18; // Default to 18 decimals
        // Call decimals() using the selector bytes since decimals() is not defined in the IERC20 interface
        (bool success, bytes memory data) = quote.staticcall(abi.encodeWithSelector(bytes4(0x313ce567)));
        if (success && data.length >= 32) {
            quoteDecimals = abi.decode(data, (uint8));
        }

        // Calculate unit amount: 10^decimals (e.g., 1e18 for 18 decimals, 1e6 for 6 decimals)
        uint256 unitAmount = 10 ** quoteDecimals;
        uint256 unitAmountOut;
        (unitAmountOut,,,) = _getQuoter().quoteExactInput(pathToUse, unitAmount);

        // Calculate exchange rate: how much base per unit of quote
        // Then multiply by amountIn to get the final quote
        // Use checked math to prevent overflow
        amountOut = unitAmountOut * amountIn / unitAmount;
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

        // Allocate memory for reversed path (same length)
        reversedPath = new bytes(len);

        assembly {
            // Get pointers to data start (skip length word)
            let srcPtr := add(poolInfo, 0x20)
            let dstPtr := add(reversedPath, 0x20)

            // Calculate number of pools: (len - 20) / 23 + 1
            let numPools := add(div(sub(len, 20), 23), 1)

            // Copy last token (20 bytes) to first position using mload/mstore
            // Load 32 bytes from last token position, extract address
            let lastTokenWord := mload(add(srcPtr, sub(len, 20)))
            let lastToken := shr(96, lastTokenWord) // Right-align address
            mstore(dstPtr, shl(96, lastToken)) // Store at start, left-aligned

            // Process intermediate pools: copy fees and tokens in reverse order
            let dstOffset := 20 // Write position starts after first token
            let srcOffset := sub(len, 23) // Start reading from second-to-last fee

            // For each intermediate pool (from pool N-1 down to pool 1)
            for { let i := 1 } lt(i, numPools) { i := add(i, 1) } {
                // Copy fee (3 bytes) from source to destination
                // Load word containing fee, extract 3 bytes (24 bits) from the start
                let feeWord := mload(add(srcPtr, srcOffset))
                let fee := shr(232, feeWord) // Extract fee (rightmost 24 bits after shift)

                // Store fee: load destination word, clear first 3 bytes, set fee
                let dstWord := mload(add(dstPtr, dstOffset))
                // Mask: keep all bytes except first 3 (0xffffff00...00)
                dstWord := and(dstWord, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00)
                // Set fee in first 3 bytes (shift left by 232 bits)
                dstWord := or(dstWord, shl(232, fee))
                mstore(add(dstPtr, dstOffset), dstWord)

                // Move source offset back 20 bytes to read token
                srcOffset := sub(srcOffset, 20)

                // Copy token (20 bytes) from source to destination
                let tokenWord := mload(add(srcPtr, srcOffset))
                let token := shr(96, tokenWord) // Extract address (right-align)

                // Store token at dstOffset + 3
                // Load word at destination, clear first 20 bytes, set token
                let tokenDstWord := mload(add(dstPtr, add(dstOffset, 3)))
                // Mask: keep last 12 bytes, clear first 20 bytes (0x0000...00ffff...ff)
                tokenDstWord := and(tokenDstWord, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
                // Set token in first 20 bytes (shift left by 96 bits)
                tokenDstWord := or(tokenDstWord, shl(96, token))
                mstore(add(dstPtr, add(dstOffset, 3)), tokenDstWord)

                // Update offsets for next iteration
                dstOffset := add(dstOffset, 23) // Move past fee (3) + token (20)

                // Only move srcOffset back if there are more pools to process
                if lt(add(i, 1), numPools) { srcOffset := sub(srcOffset, 3) } // Move back 3 bytes to next fee position
            }

            // Copy first token (20 bytes) to last position
            let firstTokenWord := mload(srcPtr)
            let firstToken := shr(96, firstTokenWord) // Extract address
            mstore(add(dstPtr, sub(len, 20)), shl(96, firstToken)) // Store at end, left-aligned
        }
    }

    function _getPermit2() private view returns (IPermit2) {
        return UniswapV3SwapperEngineStorage(SELF).permit2();
    }

    function _getQuoter() private view returns (IQuoter) {
        return UniswapV3SwapperEngineStorage(SELF).quoter();
    }

    function _getUniversalRouter() private view returns (IUniversalRouter) {
        return UniswapV3SwapperEngineStorage(SELF).universalRouter();
    }
}
