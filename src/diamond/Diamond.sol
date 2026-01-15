// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "./libraries/LibDiamond.sol";

/// @title Diamond
/// @notice Abstract base contract for EIP-2535 Diamond implementations
/// @dev Provides the standard fallback and receive functions for routing calls to facets.
///      Concrete diamond contracts should inherit from this contract to get the standard
///      function routing behavior as specified in EIP-2535.
///      See https://eips.ethereum.org/EIPS/eip-2535
abstract contract Diamond {
    /// @notice Error when function selector is not found in any facet
    /// @dev This error is thrown when a function is called that doesn't exist in any facet
    /// @param _functionSelector The function selector that was not found
    error FunctionNotFound(bytes4 _functionSelector);

    /// @notice Fallback function that delegates calls to facets based on function selector
    /// @dev As specified in EIP-2535, the fallback function:
    ///      1. Determines which facet to call based on the first four bytes of call data (function selector)
    ///      2. Executes that function from the facet using delegatecall
    ///      3. The delegatecall enables the diamond to execute the facet's function as if it was
    ///         implemented by the diamond itself
    ///      The msg.sender and msg.value remain unchanged during delegatecall
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Get facet from function selector (first 4 bytes of call data)
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        // Execute external function from facet using delegatecall
        // This allows the facet's function to execute in the context of the diamond
        assembly {
            // Copy function selector and any arguments from calldata to memory
            calldatacopy(0, 0, calldatasize())

            // Execute function call using delegatecall to the facet
            // delegatecall preserves msg.sender and msg.value
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)

            // Copy any return value from the delegatecall
            returndatacopy(0, 0, returndatasize())

            // Return any return value or revert with error back to the caller
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Receive function to accept ETH
    /// @dev Allows the diamond to receive ETH directly
    receive() external payable {}
}

