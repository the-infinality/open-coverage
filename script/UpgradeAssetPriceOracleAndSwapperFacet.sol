// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamond} from "../src/diamond/interfaces/IDiamond.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";
import {IAssetPriceOracleAndSwapper} from "../src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";

/// @title UpgradeAssetPriceOracleAndSwapperFacet
/// @notice Script to upgrade AssetPriceOracleAndSwapperFacet on an existing EigenCoverageDiamond
/// @dev This script performs a diamond cut to replace the existing facet functions with the new facet.
contract UpgradeAssetPriceOracleAndSwapperFacet is Script {
    function run() public returns (address newFacetAddress) {
        // Read configuration from environment
        address diamondAddress = vm.promptAddress("Diamond address");
        address newFacet = vm.promptAddress("New facet address");

        console.log("Upgrading to AssetPriceOracleAndSwapperFacet", newFacet);
        console.log("Diamond:", diamondAddress);

        return upgrade(diamondAddress, newFacet);
    }

    function upgrade(address diamondAddress, address newFacet) public returns (address) {
        IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);

        address currentFacet = loupe.facetAddress(IAssetPriceOracleAndSwapper.register.selector);

        vm.startBroadcast();
        // Prepare the diamond cut
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);

        // Determine the action: Replace if facet exists, Add if it doesn't
        IDiamond.FacetCutAction action = IDiamond.FacetCutAction.Replace;

        cuts[0] = IDiamond.FacetCut({
            facetAddress: newFacet,
            action: action,
            functionSelectors: AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperSelectors()
        });

        // Execute the diamond cut
        console.log("\nExecuting diamond cut...");
        console.log("Action:", action == IDiamond.FacetCutAction.Replace ? "Replace" : "Add");

        IDiamondCut(diamondAddress).diamondCut(cuts, address(0), "");

        vm.stopBroadcast();

        // Verify the upgrade
        address updatedFacet = loupe.facetAddress(IAssetPriceOracleAndSwapper.register.selector);
        require(updatedFacet == newFacet, "Upgrade verification failed: facet address mismatch");

        _logUpgradeSummary(diamondAddress, currentFacet, newFacet);

        return newFacet;
    }

    function _logUpgradeSummary(address diamondAddress, address oldFacet, address newFacet) internal pure {
        console.log("\n=== Upgrade Summary ===");
        console.log("Diamond:", diamondAddress);
        console.log("Old facet:", oldFacet);
        console.log("New facet:", newFacet);
        console.log("\nUpgrade completed successfully!");
    }
}

