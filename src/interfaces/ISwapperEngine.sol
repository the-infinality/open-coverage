// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISwapperEngine
/// @notice Interface for swapper engines
/// @author p-dealwis, Infinality
interface ISwapperEngine {
    /// @notice Error thrown when the contract is called directly instead of via delegatecall
    error OnlyDelegateCall();

    /// @notice Error thrown when the pool information is invalid
    error InvalidPoolInfo();

    /// @notice The name of the swapper engine
    function name() external pure returns (string memory);

    /// @notice Swaps with an exact amount of input tokens
    /// @dev The swapper engine must revert with OnlyDelegateCall() if the contract is called directly instead of via delegatecall
    /// @param poolInfo The pool information to use for the swap
    /// @param amountIn The exact amount of `swap` tokens to spend
    /// @param amountOutMin The minimum amount of `base` tokens to receive
    /// @param base The asset to receive (output)
    /// @param swap The asset to spend (input)
    /// @param deadline The swap deadline timestamp
    /// @return amountOut The actual amount of `base` tokens received
    function swapForInput(
        bytes memory poolInfo,
        uint256 amountIn,
        uint256 amountOutMin,
        address base,
        address swap,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Swaps to an exact amount of output tokens
    /// @dev The swapper engine must revert with OnlyDelegateCall() if the contract is called directly instead of via delegatecall
    /// @param poolInfo The pool information to use for the swap
    /// @param amountOut The exact amount of `base` tokens to receive
    /// @param amountInMax The maximum amount of `swap` tokens to spend
    /// @param base The asset to receive (output)
    /// @param swap The asset to spend (input)
    /// @param deadline The swap deadline timestamp
    /// @return amountIn The actual amount of `swap` tokens spent
    function swapForOutput(
        bytes memory poolInfo,
        uint256 amountOut,
        uint256 amountInMax,
        address base,
        address swap,
        uint256 deadline
    ) external returns (uint256 amountIn);

    /// @notice Quotes the amount of `base` that is equivalent to `amountIn` of `quote`.
    /// @param poolInfo The pool information to use for the quote
    /// @param amountIn The amount of `quote` to get value for `base`.
    /// @param base The asset to quote the value for
    /// @param quote The asset to get value from
    /// @return amountOut The amount of `base` that is equivalent to `amountIn` of `quote`.
    function getQuote(bytes memory poolInfo, uint256 amountIn, address base, address quote)
        external
        view
        returns (uint256 amountOut);

    /// @notice Quotes the amount of `quote` required to receive `amountOut` of `base`.
    /// @param poolInfo The pool information to use for the quote
    /// @param amountOut The desired amount of `base`
    /// @param base The asset to receive
    /// @param quote The asset to spend
    /// @return amountIn The amount of `quote` required
    function getQuoteForOutput(bytes memory poolInfo, uint256 amountOut, address base, address quote)
        external
        view
        returns (uint256 amountIn);

    /// @notice Called when the swapper engine is initialized
    function onInit(bytes memory poolInfo) external;
}
