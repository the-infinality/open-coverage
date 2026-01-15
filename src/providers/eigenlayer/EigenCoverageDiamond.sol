// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {IERC165} from "src/diamond/interfaces/IERC165.sol";
import {Diamond} from "src/diamond/Diamond.sol";
import {LibDiamond} from "src/diamond/libraries/LibDiamond.sol";
import {EigenAddresses} from "./Types.sol";
import {EigenCoverageStorage} from "./EigenCoverageStorage.sol";
import {AssetPriceOracleAndSwapperStorage} from "../../storage/AssetPriceOracleAndSwapperStorage.sol";
import {IEigenServiceManager} from "./interfaces/IEigenServiceManager.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";

/// @title EigenCoverageDiamond
/// @author p-dealwis, Infinality
/// @notice EIP-2535 Diamond proxy for Eigen coverage management
/// @dev Uses the diamond pattern with fallback-based selector routing.
///      All function calls are routed to the appropriate facet via delegatecall.
contract EigenCoverageDiamond is Diamond, EigenCoverageStorage, AssetPriceOracleAndSwapperStorage, IDiamondCut {
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
        ds.supportedInterfaces[type(IEigenServiceManager).interfaceId] = true;
        ds.supportedInterfaces[type(IAssetPriceOracleAndSwapper).interfaceId] = true;
        ds.supportedInterfaces[type(ICoverageProvider).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;

        // Initialize app-specific storage
        _eigenAddresses = _args.eigenAddresses;

        // Initialize default swap slippage (1%)
        _initializeSwapSlippage();

        // Update AVS metadata URI (required for AVS registration)
        // Note: This is called directly during construction; post-deployment updates should use
        // IEigenServiceManager.updateAVSMetadataURI() via the facet
        _initializeAVSMetadataURI(_args.metadataURI);
    }

    /// @notice Updates the metadata URI for the AVS during initialization
    /// @dev This is only used during construction before facets are callable
    /// @param _metadataUri is the metadata URI for the AVS
    function _initializeAVSMetadataURI(string memory _metadataUri) private {
        IAllocationManager(_eigenAddresses.allocationManager).updateAVSMetadataURI(address(this), _metadataUri);
    }

    /// @inheritdoc IDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}

