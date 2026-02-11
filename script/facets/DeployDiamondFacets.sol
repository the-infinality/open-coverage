// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DiamondFacetsDeployer} from "utils/deployments/DiamondFacetsDeployer.sol";
import {DeploymentUtils} from "utils/deployments/DeploymentUtils.sol";
import {DiamondCutFacet} from "src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "src/diamond/facets/OwnershipFacet.sol";

/// @title DeployDiamondFacets
/// @notice Script to deploy core diamond facets (DiamondCut, DiamondLoupe, Ownership) and record them in config/deployments.json
/// @dev If facet deployments already exist for the chain, prompts to type 'y' to override.
///
/// Usage:
///   forge script script/DeployDiamondFacets.sol:DeployDiamondFacets \
///     --rpc-url <rpc-url> --broadcast --private-key <key>
contract DeployDiamondFacets is Script {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    string constant DIAMOND_CUT_FACET = "DiamondCutFacet";
    string constant DIAMOND_LOUPE_FACET = "DiamondLoupeFacet";
    string constant OWNERSHIP_FACET = "OwnershipFacet";

    function run() public returns (address[] memory facetAddresses) {
        _requireOverrideIfExistingDeployments();

        vm.startBroadcast();

        console.log("Deploying diamond facets...");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);

        (DiamondCutFacet diamondCutFacet, DiamondLoupeFacet diamondLoupeFacet, OwnershipFacet ownershipFacet) =
            DiamondFacetsDeployer.deployDiamondFacets();

        facetAddresses = new address[](3);
        facetAddresses[0] = address(diamondCutFacet);
        facetAddresses[1] = address(diamondLoupeFacet);
        facetAddresses[2] = address(ownershipFacet);

        vm.stopBroadcast();

        _logSummary(facetAddresses);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeployments(facetAddresses);
        } else {
            console.log("Dry run - skipping deployments.json update");
        }

        return facetAddresses;
    }

    function _logSummary(address[] memory facetAddresses) internal pure {
        console.log("\n=== Deployment Summary ===");
        console.log(DIAMOND_CUT_FACET, ":", facetAddresses[0]);
        console.log(DIAMOND_LOUPE_FACET, ":", facetAddresses[1]);
        console.log(OWNERSHIP_FACET, ":", facetAddresses[2]);
    }

    function _requireOverrideIfExistingDeployments() internal {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory chainPath = string.concat(".", chainId);
            try vm.parseJsonKeys(json, chainPath) returns (string[] memory keys) {
                if (keys.length == 0) return;
                string[3] memory facetNames = [DIAMOND_CUT_FACET, DIAMOND_LOUPE_FACET, OWNERSHIP_FACET];
                bool anyExist;
                for (uint256 k = 0; k < keys.length; k++) {
                    for (uint256 f = 0; f < 3; f++) {
                        if (keccak256(abi.encodePacked(keys[k])) == keccak256(abi.encodePacked(facetNames[f]))) {
                            anyExist = true;
                            break;
                        }
                    }
                    if (anyExist) break;
                }
                if (!anyExist) return;
                string[3] memory artifacts = [
                    "src/diamond/facets/DiamondCutFacet.sol:DiamondCutFacet",
                    "src/diamond/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet",
                    "src/diamond/facets/OwnershipFacet.sol:OwnershipFacet"
                ];
                bool allSameBytecode = true;
                for (uint256 f = 0; f < 3; f++) {
                    bool facetExists;
                    for (uint256 k = 0; k < keys.length; k++) {
                        if (keccak256(abi.encodePacked(keys[k])) == keccak256(abi.encodePacked(facetNames[f]))) {
                            facetExists = true;
                            break;
                        }
                    }
                    if (facetExists) {
                        address a = vm.parseJsonAddress(json, string.concat(chainPath, ".", facetNames[f]));
                        bytes memory onChain = a.code;
                        bytes memory compiled = vm.getDeployedCode(artifacts[f]);
                        if (
                            onChain.length == 0 || compiled.length == 0
                                || !DeploymentUtils.bytecodeMatches(onChain, compiled)
                        ) {
                            allSameBytecode = false;
                            break;
                        }
                    }
                }
                if (allSameBytecode) {
                    string memory input = vm.prompt(
                        string.concat(
                            "Facet deployments already exist for chain ",
                            chainId,
                            ".\n",
                            "Bytecode is identical. Recommended to use the existing contracts.\n",
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
                            "Facet deployments already exist for chain ",
                            chainId,
                            ".\n",
                            "Type 'y' to override existing deployment properties and continue: "
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

    function _saveDeployments(address[] memory facetAddresses) internal {
        string memory chainId = vm.toString(block.chainid);
        string[3] memory names = [DIAMOND_CUT_FACET, DIAMOND_LOUPE_FACET, OWNERSHIP_FACET];
        for (uint256 i = 0; i < 3; i++) {
            string memory jsonPath = string.concat(".", chainId, ".", names[i]);
            vm.writeJson(vm.toString(facetAddresses[i]), DEPLOYMENTS_PATH, jsonPath);
        }
        console.log("\nSaved all facet deployments to", DEPLOYMENTS_PATH, "for chain", chainId);
    }
}
