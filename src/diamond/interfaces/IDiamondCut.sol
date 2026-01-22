// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamond} from "./IDiamond.sol";
import {IDiamondOwner} from "./IDiamondOwner.sol";

/// @title IDiamondCut
/// @author EIP-2535 Diamonds
/// @notice Interface for adding/replacing/removing facet functions in a diamond
/// @dev See https://eips.ethereum.org/EIPS/eip-2535
///      This interface extends IDiamond and adds the diamondCut function.
///      It is part of the EIP-2535 Diamond standard specification.
interface IDiamondCut is IDiamond, IDiamondOwner {
    /// @notice Add/replace/remove any number of functions and optionally execute a function with delegatecall
    /// @dev As specified in EIP-2535. This function allows arbitrary execution via delegatecall,
    ///      so access must be carefully restricted (typically to contract owner).
    ///      The function uses the FacetCut struct and FacetCutAction enum defined in IDiamond.
    /// @param _diamondCut The facet cuts to execute atomically
    /// @param _init The address of the contract or facet to execute _calldata (can be address(0))
    /// @param _calldata A function call, including function selector and arguments.
    ///                  _calldata is executed with delegatecall on _init.
    ///                  Can be empty if _init is address(0)
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
}
