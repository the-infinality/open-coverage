// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "./libraries/LibDiamond.sol";

/// @title Diamond
/// @notice Abstract base contract for EIP-2535 Diamond implementations
/// @dev Provides the standard fallback and receive functions for routing calls to facets.
///      Concrete diamond contracts should inherit from this contract to get the standard
///      function routing behavior.
abstract contract Diamond {
    /// @notice Error when function selector is not found in any facet
    error FunctionNotFound(bytes4 _functionSelector);

    /// @notice Fallback function that delegates calls to facets based on function selector
    /// @dev Find facet for function that is called and execute the function if found
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Get facet from function selector
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        // Execute external function from facet using delegatecall
        assembly {
            // Copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())

            // Execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)

            // Get any return value
            returndatacopy(0, 0, returndatasize())

            // Return any return value or error back to the caller
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Receive function to accept ETH
    receive() external payable {}
}

