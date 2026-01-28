// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AssetPriceOracleAndSwapperFacet} from "../src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";

/// @title DeployAssetPriceOracleAndSwapperFacet
/// @notice Script to deploy a new version of AssetPriceOracleAndSwapperFacet
/// @dev This script deploys the facet standalone, to be used with UpgradeAssetPriceOracleAndSwapperFacet
///      for upgrading existing diamond proxies.
///
/// Usage:
///   forge script script/DeployAssetPriceOracleAndSwapperFacet.sol:DeployAssetPriceOracleAndSwapperFacet \
///     --account <account> --sender <sender> --rpc-url <rpc-url> --chain-id <chain-id> --broadcast
contract DeployAssetPriceOracleAndSwapperFacet is Script {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    function run() public returns (address facetAddress) {
        vm.startBroadcast();

        console.log("Deploying new AssetPriceOracleAndSwapperFacet...");
        console.log("Deployer:", msg.sender);
        console.log("Chain ID:", block.chainid);

        // Deploy the facet
        AssetPriceOracleAndSwapperFacet facet =
            AssetPriceOracleAndSwapperFacetDeployer.deployAssetPriceOracleAndSwapperFacet();
        facetAddress = address(facet);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("AssetPriceOracleAndSwapperFacet deployed at:", facetAddress);

        // Only save deployed address when actually broadcasting (not dry run)
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeployment(facetAddress);
            console.log("Deployment saved to:", DEPLOYMENTS_PATH);
        } else {
            console.log("Dry run - skipping deployment file update");
        }

        console.log("\nNext step: Use UpgradeAssetPriceOracleAndSwapperFacet.sol to upgrade your diamond");

        return facetAddress;
    }

    function _saveDeployment(address facetAddress) internal {
        // Build the JSON path for this chain's deployment
        string memory chainId = vm.toString(block.chainid);
        string memory jsonPath = string.concat(".", chainId, ".AssetPriceOracleAndSwapperFacet");

        // Write the address to the deployments file
        vm.writeJson(vm.toString(facetAddress), DEPLOYMENTS_PATH, jsonPath);

        console.log("\nSaved deployment to deployments.json:");
        console.log("  Chain ID:", chainId);
        console.log("  Key: AssetPriceOracleAndSwapperFacet");
        console.log("  Address:", facetAddress);
    }
}

