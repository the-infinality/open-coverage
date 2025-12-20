// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamondLoupe
/// @author EIP-2535 Diamonds
/// @notice Interface for introspecting a diamond's facets and their functions
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
interface IDiamondLoupe {
    /// @notice A facet and its function selectors
    /// @param facetAddress The address of the facet
    /// @param functionSelectors The function selectors belonging to this facet
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Gets all facet addresses and their function selectors
    /// @return facets_ Array of Facet structs
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Gets all the function selectors provided by a facet
    /// @param _facet The facet address
    /// @return facetFunctionSelectors_ Array of function selectors
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    /// @notice Get all the facet addresses used by a diamond
    /// @return facetAddresses_ Array of facet addresses
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Gets the facet that supports the given selector
    /// @dev If facet is not found return address(0)
    /// @param _functionSelector The function selector
    /// @return facetAddress_ The facet address
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}

