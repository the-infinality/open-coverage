// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "../../../src/interfaces/IPriceOracle.sol";

/// @notice Oracle that always returns 0 for getQuote; used to force verified=false when used with SwapperVerified.
contract MockPriceOracleZero is IPriceOracle {
    function name() external pure returns (string memory) {
        return "MockPriceOracleZero";
    }

    function getQuote(uint256, address, address) external pure returns (uint256) {
        return 0;
    }

    function getQuotes(uint256, address, address) external pure returns (uint256 bidOutAmount, uint256 askOutAmount) {
        return (0, 0);
    }
}
