// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamondCut
/// @author EIP-2535 Diamonds
/// @notice Interface for adding/replacing/removing facet functions in a diamond
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
interface IDiamondCut {
    /// @notice The action to perform on a facet's functions
    enum FacetCutAction {
        Add, // Add new functions
        Replace, // Replace existing functions
        Remove // Remove existing functions
    }

    /// @notice A facet cut describes changes to make to a facet
    /// @param facetAddress The address of the facet to modify
    /// @param action The action to perform (Add, Replace, Remove)
    /// @param functionSelectors The function selectors to add/replace/remove
    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Emitted when facet functions are added, replaced, or removed
    /// @param _diamondCut The facet cuts that were executed
    /// @param _init The address of the contract to execute _calldata on
    /// @param _calldata The calldata to execute on _init
    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);

    /// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
    /// @param _diamondCut The facet cuts to execute
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}

