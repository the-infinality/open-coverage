// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IDiamondOwner} from "../interfaces/IDiamondOwner.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title DiamondCutFacet
/// @author EIP-2535 Diamonds
/// @notice Facet for adding/replacing/removing diamond functions
/// @dev Implements IDiamondCut interface as specified in EIP-2535.
///      This facet provides the diamondCut function which allows adding, replacing,
///      or removing functions atomically. Access to this function must be carefully
///      restricted (typically to contract owner) as it allows arbitrary execution.
///      See https://eips.ethereum.org/EIPS/eip-2535
contract DiamondCutFacet is IDiamondCut {
    /// @inheritdoc IDiamondCut
    /// @dev Only callable by the contract owner
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @inheritdoc IDiamondOwner
    /// @dev As specified in EIP-2535. This function returns the address of the contract owner.
    /// @return owner The address of the contract owner
    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @inheritdoc IDiamondOwner
    function setOwner(address newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(newOwner);
    }
}
