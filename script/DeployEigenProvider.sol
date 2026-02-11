// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenHelper, EigenAddressbook} from "../utils/EigenHelper.sol";
import {UniswapHelper, UniswapAddressbook} from "../utils/UniswapHelper.sol";
import {EigenCoverageDiamond} from "../src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {DiamondCutFacet} from "../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/diamond/facets/DiamondLoupeFacet.sol";
import {EigenServiceManagerFacet} from "../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {AssetPriceOracleAndSwapperFacet} from "../src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {EigenAddresses} from "../src/providers/eigenlayer/Types.sol";
import {DiamondFacetsDeployer} from "../utils/deployments/DiamondFacetsDeployer.sol";
import {EigenFacetsDeployer} from "../utils/deployments/EigenFacetsDeployer.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";
import {OwnershipFacet} from "../src/diamond/facets/OwnershipFacet.sol";

/// @title DeployEigenProvider
/// @notice Script to deploy EigenCoverageDiamond with all facets
/// @dev Uses helper libraries to deploy facets in a modular way
contract DeployEigenProvider is Script, EigenHelper, UniswapHelper {
    function run() public returns (address eigenCoverageDiamondAddress) {
        vm.startBroadcast();

        address owner = msg.sender;
        string memory metadataURI = vm.envOr("AVS_METADATA_URI", string("https://coverage.example.com/metadata.json"));

        console.log("Deploying EigenCoverageDiamond...");
        console.log("Owner:", owner);
        console.log("Metadata URI:", metadataURI);

        // Deploy all facets and get cuts
        IDiamondCut.FacetCut[] memory cuts = _deployAllFacets();

        // Deploy diamond
        console.log("\nDeploying EigenCoverageDiamond...");
        EigenCoverageDiamond.DiamondArgs memory args = _prepareDiamondArgs(owner, metadataURI);
        EigenCoverageDiamond eigenCoverageDiamond = new EigenCoverageDiamond(cuts, args);
        eigenCoverageDiamondAddress = address(eigenCoverageDiamond);

        _logDeploymentSummary(eigenCoverageDiamondAddress, cuts);

        vm.stopBroadcast();

        return eigenCoverageDiamondAddress;
    }

    function _deployAllFacets() internal returns (IDiamondCut.FacetCut[] memory cuts) {
        console.log("\nDeploying facets...");

        // Deploy diamond core facets
        (DiamondCutFacet diamondCutFacet, DiamondLoupeFacet diamondLoupeFacet, OwnershipFacet ownershipFacet) =
            DiamondFacetsDeployer.deployDiamondFacets();
        console.log("DiamondCutFacet deployed at:", address(diamondCutFacet));
        console.log("DiamondLoupeFacet deployed at:", address(diamondLoupeFacet));

        // Deploy Eigen-specific facets
        (EigenServiceManagerFacet eigenServiceManagerFacet, EigenCoverageProviderFacet eigenCoverageProviderFacet) =
            EigenFacetsDeployer.deployEigenFacets();
        console.log("EigenServiceManagerFacet deployed at:", address(eigenServiceManagerFacet));
        console.log("EigenCoverageProviderFacet deployed at:", address(eigenCoverageProviderFacet));

        // Deploy AssetPriceOracleAndSwapperFacet
        AssetPriceOracleAndSwapperFacet assetPriceOracleAndSwapperFacet =
            AssetPriceOracleAndSwapperFacetDeployer.deployAssetPriceOracleAndSwapperFacet();
        console.log("AssetPriceOracleAndSwapperFacet deployed at:", address(assetPriceOracleAndSwapperFacet));

        // Prepare diamond cut with all facets (5 facets total)
        cuts = new IDiamondCut.FacetCut[](5);

        // Get facet cuts from helper libraries
        IDiamondCut.FacetCut[] memory diamondCuts =
            DiamondFacetsDeployer.getDiamondFacetCuts(diamondCutFacet, diamondLoupeFacet, ownershipFacet);
        IDiamondCut.FacetCut[] memory eigenCuts =
            EigenFacetsDeployer.getEigenFacetCuts(eigenServiceManagerFacet, eigenCoverageProviderFacet);
        IDiamondCut.FacetCut memory assetPriceOracleAndSwapperCut =
            AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperFacetCut(
                assetPriceOracleAndSwapperFacet
            );

        // Combine all facet cuts
        cuts[0] = diamondCuts[0]; // DiamondCutFacet
        cuts[1] = diamondCuts[1]; // DiamondLoupeFacet
        cuts[2] = eigenCuts[0]; // EigenServiceManagerFacet
        cuts[3] = eigenCuts[1]; // EigenCoverageProviderFacet
        cuts[4] = assetPriceOracleAndSwapperCut; // AssetPriceOracleAndSwapperFacet
    }

    function _prepareDiamondArgs(address owner, string memory metadataURI)
        internal
        view
        returns (EigenCoverageDiamond.DiamondArgs memory)
    {
        EigenAddressbook memory eigenAddressBook = _getAddressBook();
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        return EigenCoverageDiamond.DiamondArgs({
            owner: owner,
            eigenAddresses: EigenAddresses({
                allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
                delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
                strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
                rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
                permissionController: eigenAddressBook.eigenAddresses.permissionController
            }),
            metadataURI: metadataURI,
            universalRouter: uniswapAddressBook.uniswapAddresses.universalRouter,
            permit2: uniswapAddressBook.uniswapAddresses.permit2
        });
    }

    function _logDeploymentSummary(address eigenCoverageDiamondAddress, IDiamondCut.FacetCut[] memory cuts)
        internal
        pure
    {
        console.log("\n=== Deployment Summary ===");
        console.log("EigenCoverageDiamond deployed at:", eigenCoverageDiamondAddress);
        console.log("DiamondCutFacet:", cuts[0].facetAddress);
        console.log("DiamondLoupeFacet:", cuts[1].facetAddress);
        console.log("EigenServiceManagerFacet:", cuts[2].facetAddress);
        console.log("EigenCoverageProviderFacet:", cuts[3].facetAddress);
        console.log("AssetPriceOracleAndSwapperFacet:", cuts[4].facetAddress);
    }
}
