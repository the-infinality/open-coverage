// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "../../src/mixins/AssetPriceOracleAndSwapper.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 public multiplier;
    address public asset1;
    address public asset2;

    constructor(uint256 multiplier_, address asset1_, address asset2_) {
        asset1 = asset1_;
        asset2 = asset2_;
        multiplier = multiplier_;
    }

    function setMultiplier(uint256 multiplier_) external {
        multiplier = multiplier_;
    }

    function name() external pure returns (string memory) {
        return "MockPriceOracle";
    }

    function getQuote(uint256 amountIn, address base_, address) external view returns (uint256) {
        return multiply(amountIn, base_);
    }

    function getQuotes(uint256 amountIn, address base_, address)
        external
        view
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        return (multiply(amountIn, base_), multiply(amountIn, base_));
    }

    function multiply(uint256 amount, address base_) private view returns (uint256) {
        if(base_ == asset1) {
            return amount * (multiplier / 1e18);
        } else if(base_ == asset2) {
            return amount * 1e18 / multiplier;
        } else {
            revert("Invalid asset");
        }
    }
}

