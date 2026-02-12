// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock strategy for testing whitelist behavior with same underlying asset
contract MockStrategy {
    IERC20 private _underlyingToken;

    constructor(address underlyingToken_) {
        _underlyingToken = IERC20(underlyingToken_);
    }

    function underlyingToken() external view returns (IERC20) {
        return _underlyingToken;
    }
}
