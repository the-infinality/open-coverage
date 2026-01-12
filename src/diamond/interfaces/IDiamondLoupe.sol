// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamondLoupe
/// @author EIP-2535 Diamonds
/// @notice Interface for introspecting a diamond's facets and their functions
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
///      This interface is part of the EIP-2535 Diamond standard specification.
///      The interface ID is calculated as:
///      IDiamondLoupe.facets.selector ^ IDiamondLoupe.facetFunctionSelectors.selector ^
///      IDiamondLoupe.facetAddresses.selector ^ IDiamondLoupe.facetAddress.selector
interface IDiamondLoupe {
    /// @notice A facet and its function selectors
    /// @dev As specified in EIP-2535
    /// @param facetAddress The address of the facet
    /// @param functionSelectors The function selectors belonging to this facet
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Gets all facet addresses and their function selectors
    /// @dev As specified in EIP-2535. This is one of the four standard loupe functions.
    /// @return facets_ Array of Facet structs containing all facets and their selectors
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Gets all the function selectors provided by a facet
    /// @dev As specified in EIP-2535. This is one of the four standard loupe functions.
    /// @param _facet The facet address
    /// @return facetFunctionSelectors_ Array of function selectors for the given facet
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    /// @notice Get all the facet addresses used by a diamond
    /// @dev As specified in EIP-2535. This is one of the four standard loupe functions.
    /// @return facetAddresses_ Array of facet addresses
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Gets the facet that supports the given selector
    /// @dev As specified in EIP-2535. This is one of the four standard loupe functions.
    ///      If facet is not found, returns address(0)
    /// @param _functionSelector The function selector to look up
    /// @return facetAddress_ The facet address that implements the selector, or address(0) if not found
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}

