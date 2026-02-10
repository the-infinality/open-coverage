// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockFacet
/// @notice Simple facet with one function for testing diamond add/replace/remove
contract MockFacet {
    function getValue() external pure returns (uint256) {
        return 42;
    }

    function getOtherValue() external pure returns (uint256) {
        return 100;
    }
}
