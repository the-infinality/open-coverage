// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice Interface for a price oracle that provides asset quotes
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

