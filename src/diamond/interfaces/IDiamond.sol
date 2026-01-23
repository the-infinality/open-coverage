// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamond
/// @author EIP-2535 Diamonds
/// @notice Base interface for EIP-2535 Diamond standard
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
///      This interface defines the core types and events used by diamonds.
///      IDiamondCut extends this interface to add the diamondCut function.
interface IDiamond {
    /// @notice The action to perform on a facet's functions
    /// @dev As specified in EIP-2535
    ///      Add=0, Replace=1, Remove=2
    enum FacetCutAction {
        Add, // Add new functions
        Replace, // Replace existing functions
        Remove // Remove existing functions
    }

    /// @notice A facet cut describes changes to make to a facet
    /// @dev As specified in EIP-2535
    /// @param facetAddress The address of the facet to modify. Must be address(0) for Remove action
    /// @param action The action to perform (Add, Replace, Remove)
    /// @param functionSelectors The function selectors to add/replace/remove
    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Emitted when facet functions are added, replaced, or removed
    /// @dev As specified in EIP-2535. This event enables transparency and tracking of diamond upgrades.
    ///      All changes to a diamond are recorded through this event, allowing for a complete
    ///      historical record of upgrades.
    /// @param _diamondCut The facet cuts that were executed
    /// @param _init The address of the contract to execute _calldata on (can be address(0))
    /// @param _calldata The calldata to execute on _init (can be empty)
    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}
