// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";

import {IDiamondCut} from "../../diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../diamond/interfaces/IDiamondLoupe.sol";
import {IERC165} from "../../diamond/interfaces/IERC165.sol";
import {LibDiamond} from "../../diamond/libraries/LibDiamond.sol";
import {EigenAddresses} from "./Types.sol";
import {EigenCoverageStorage} from "./EigenCoverageStorage.sol";
import {AssetPriceOracleAndSwapper} from "../../mixins/AssetPriceOracleAndSwapper.sol";

/// @title EigenCoverageDiamond
/// @author p-dealwis, Infinality
/// @notice EIP-2535 Diamond proxy for Eigen coverage management
/// @dev Uses the diamond pattern with fallback-based selector routing.
///      All function calls are routed to the appropriate facet via delegatecall.
contract EigenCoverageDiamond is EigenCoverageStorage, AssetPriceOracleAndSwapper {
    /// @notice Error when function selector is not found in any facet
    error FunctionNotFound(bytes4 _functionSelector);

    /// @notice Struct for initialization arguments
    struct DiamondArgs {
        address owner;
        EigenAddresses eigenAddresses;
        string metadataURI;
        address universalRouter;
        address permit2;
    }

    /// @notice Initialize the diamond with facets and app-specific configuration
    /// @param _diamondCut The initial facet cuts to add
    /// @param _args The initialization arguments
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, DiamondArgs memory _args) {
        // Set the contract owner
        LibDiamond.setContractOwner(_args.owner);

        // Execute the diamond cut to add initial facets
        LibDiamond.diamondCut(_diamondCut, address(0), "");

        // Register supported interfaces
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;

        // Initialize app-specific storage
        _eigenAddresses = _args.eigenAddresses;

        // Initialize the AssetPriceOracleAndSwapper mixin
        __AssetPriceOracleAndSwapper_init(_args.universalRouter, _args.permit2);

        // Update AVS metadata URI (required for AVS registration)
        _updateAVSMetadataURI(_args.metadataURI);
    }

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

    /// @notice Updates the metadata URI for the AVS
    /// @param _metadataUri is the metadata URI for the AVS
    function _updateAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
    }
}

