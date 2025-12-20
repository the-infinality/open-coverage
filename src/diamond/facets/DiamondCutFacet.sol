// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title DiamondCutFacet
/// @author EIP-2535 Diamonds
/// @notice Facet for adding/replacing/removing diamond functions
/// @dev Implements IDiamondCut interface
contract DiamondCutFacet is IDiamondCut {
    /// @inheritdoc IDiamondCut
    /// @dev Only callable by the contract owner
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}

