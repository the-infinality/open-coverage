// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AssetPriceOracleAndSwapperFacet} from "src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {AssetPriceOracleAndSwapperFacetDeployer} from "utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";
import {DeploymentUtils} from "utils/deployments/DeploymentUtils.sol";

/// @title DeployAssetPriceOracleAndSwapperFacet
/// @notice Script to deploy a new version of AssetPriceOracleAndSwapperFacet
/// @dev This script deploys the facet standalone, to be used with UpgradeAssetPriceOracleAndSwapperFacet
///      for upgrading existing diamond proxies. If a deployment already exists for the chain,
///      prompts to type 'y' to override before continuing.
///
/// Usage:
///   forge script script/DeployAssetPriceOracleAndSwapperFacet.sol:DeployAssetPriceOracleAndSwapperFacet \
///     --account <account> --sender <sender> --rpc-url <rpc-url> --chain-id <chain-id> --broadcast
contract DeployAssetPriceOracleAndSwapperFacet is Script {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";
    string constant ASSET_PRICE_ORACLE_AND_SWAPPER_FACET = "AssetPriceOracleAndSwapperFacet";

    function run() public returns (address facetAddress) {
        _requireOverrideIfExistingDeployment();

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

    function _requireOverrideIfExistingDeployment() internal {
        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory chainPath = string.concat(".", chainId);
            try vm.parseJsonKeys(json, chainPath) returns (string[] memory keys) {
                bool exists;
                for (uint256 k = 0; k < keys.length; k++) {
                    if (
                        keccak256(abi.encodePacked(keys[k]))
                            == keccak256(abi.encodePacked(ASSET_PRICE_ORACLE_AND_SWAPPER_FACET))
                    ) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) return;
                address existingAddr =
                    vm.parseJsonAddress(json, string.concat(chainPath, ".", ASSET_PRICE_ORACLE_AND_SWAPPER_FACET));
                bytes memory onChain = existingAddr.code;
                bytes memory compiled = vm.getDeployedCode(
                    "src/facets/AssetPriceOracleAndSwapperFacet.sol:AssetPriceOracleAndSwapperFacet"
                );
                bool bytecodeSame =
                    onChain.length > 0 && compiled.length > 0 && DeploymentUtils.bytecodeMatches(onChain, compiled);
                if (bytecodeSame) {
                    string memory input = vm.prompt(
                        string.concat(
                            "AssetPriceOracleAndSwapperFacet deployment already exists for chain ",
                            chainId,
                            ".\n",
                            "Bytecode is identical. Recommended to use the existing contract.\n",
                            "Type 'y' to deploy anyway (override): "
                        )
                    );
                    require(
                        keccak256(abi.encodePacked(input)) == keccak256(abi.encodePacked("y")),
                        "Deployment cancelled (expected 'y' to override)"
                    );
                } else {
                    string memory input = vm.prompt(
                        string.concat(
                            "AssetPriceOracleAndSwapperFacet deployment already exists for chain ",
                            chainId,
                            ".\n",
                            "Type 'y' to override existing deployment and continue: "
                        )
                    );
                    require(
                        keccak256(abi.encodePacked(input)) == keccak256(abi.encodePacked("y")),
                        "Deployment cancelled (expected 'y' to override)"
                    );
                }
            } catch {}
        } catch {}
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

