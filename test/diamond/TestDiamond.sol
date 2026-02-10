// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Diamond} from "src/diamond/Diamond.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {IDiamondOwner} from "src/diamond/interfaces/IDiamondOwner.sol";
import {IERC165} from "src/diamond/interfaces/IERC165.sol";

/// @title TestDiamond
/// @notice Minimal EIP-2535 Diamond implementation for testing the diamond core
/// @dev No app-specific storage; only core facets (DiamondCut, DiamondLoupe) and standard interfaces
contract TestDiamond is Diamond {
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, address _owner) {
        LibDiamond.diamondCut(_diamondCut, address(0), "");
        LibDiamond.setContractOwner(_owner);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondOwner).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    }
}
