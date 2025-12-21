// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISwapperEngine
/// @notice Interface for swapper engines
/// @author p-dealwis, Infinality
interface ISwapperEngine {
    /// @notice Error thrown when the contract is called directly instead of via delegatecall
    error OnlyDelegateCall();

    /// @notice The name of the swapper engine
    function name() external pure returns (string memory);

    /// @notice Swaps with an exact amount of input tokens
    /// @dev The swapper engine must revert with OnlyDelegateCall() if the contract is called directly instead of via delegatecall
    /// @param poolInfo The pool information to use for the swap
    /// @param amountIn The exact amount of tokens to spend
    /// @param amountOutMin The minimum amount of tokens to receive
    /// @param base The asset to swap from
    /// @param swap The asset to swap to
    /// @return amountOut The actual amount of output tokens received
    function swapForInput(bytes memory poolInfo, uint256 amountIn, uint256 amountOutMin, address base, address swap)
        external
        returns (uint256 amountOut);

    /// @notice Swaps to an exact amount of output tokens
    /// @dev The swapper engine must revert with OnlyDelegateCall() if the contract is called directly instead of via delegatecall
    /// @param poolInfo The pool information to use for the swap
    /// @param amountOut The exact amount of tokens to receive
    /// @param amountInMax The maximum amount of tokens to spend
    /// @param base The asset to swap from
    /// @param swap The asset to swap to
    /// @return amountIn The actual amount of input tokens spent
    function swapForOutput(bytes memory poolInfo, uint256 amountOut, uint256 amountInMax, address base, address swap)
        external
        returns (uint256 amountIn);

    /// @notice Quotes the amount of `quote` that is equivalent to `amountIn` of `base`.
    /// @param poolInfo The pool information to use for the quote
    /// @param amountIn The amount of `base` to get value for `quote`.
    /// @param base The asset to get value for
    /// @param quote The asset to quote from
    /// @return amountOut The amount of `quote` that is equivalent to `amountIn` of `base`.
    function getQuote(bytes memory poolInfo, uint256 amountIn, address base, address quote)
        external
        returns (uint256 amountOut);
}
