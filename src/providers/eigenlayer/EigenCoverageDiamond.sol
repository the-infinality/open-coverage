// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondOwner} from "src/diamond/interfaces/IDiamondOwner.sol";
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

/// @title EigenCoverageDiamond
/// @author p-dealwis, Infinality
/// @notice EIP-2535 Diamond proxy for Eigen coverage management
/// @dev Uses the diamond pattern with fallback-based selector routing.
///      All function calls are routed to the appropriate facet via delegatecall.
contract EigenCoverageDiamond is Diamond, EigenCoverageStorage, AssetPriceOracleAndSwapperStorage {
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
        // Execute the diamond cut to add initial facets
        LibDiamond.diamondCut(_diamondCut, address(0), "");

        // Set the contract owner
        LibDiamond.setContractOwner(_args.owner);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Register supported interfaces
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondOwner).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;

        ds.supportedInterfaces[type(IEigenServiceManager).interfaceId] = true;
        ds.supportedInterfaces[type(IAssetPriceOracleAndSwapper).interfaceId] = true;
        ds.supportedInterfaces[type(ICoverageProvider).interfaceId] = true;

        // Initialize app-specific storage
        _eigenAddresses = _args.eigenAddresses;

        // Update AVS metadata URI (required for AVS registration)
        IAllocationManager(_args.eigenAddresses.allocationManager)
            .updateAVSMetadataURI(address(this), _args.metadataURI);

        // Initialize default swap slippage (1%)
        _initializeSwapSlippage();
    }
}
