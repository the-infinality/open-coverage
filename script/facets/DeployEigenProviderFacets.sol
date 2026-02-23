// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {EigenFacetsDeployer} from "../../utils/deployments/EigenFacetsDeployer.sol";
import {DeploymentUtils} from "../../utils/deployments/DeploymentUtils.sol";
import {EigenServiceManagerFacet} from "../../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "../../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";

/// @title DeployEigenProviderFacets
/// @notice Script to deploy Eigen provider facets (EigenServiceManager, EigenCoverageProvider) and record them in config/deployments.json
/// @dev If facet deployments already exist for the chain, prompts to type 'y' to override.
///
/// Usage:
///   forge script script/DeployEigenProviderFacets.sol:DeployEigenProviderFacets \
///     --rpc-url <rpc-url> --broadcast --private-key <key>
contract DeployEigenProviderFacets is Script {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    string constant EIGEN_SERVICE_MANAGER_FACET = "EigenServiceManagerFacet";
    string constant EIGEN_COVERAGE_PROVIDER_FACET = "EigenCoverageProviderFacet";

    function run() public returns (address[] memory facetAddresses) {
        _requireOverrideIfExistingDeployments();

        vm.startBroadcast();

        console.log("Deploying Eigen provider facets...");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);

        (EigenServiceManagerFacet eigenServiceManagerFacet, EigenCoverageProviderFacet eigenCoverageProviderFacet) =
            EigenFacetsDeployer.deployEigenFacets();

        facetAddresses = new address[](2);
        facetAddresses[0] = address(eigenServiceManagerFacet);
        facetAddresses[1] = address(eigenCoverageProviderFacet);

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
        console.log(EIGEN_SERVICE_MANAGER_FACET, ":", facetAddresses[0]);
        console.log(EIGEN_COVERAGE_PROVIDER_FACET, ":", facetAddresses[1]);
    }

    function _requireOverrideIfExistingDeployments() internal {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory chainPath = string.concat(".", chainId);
            try vm.parseJsonKeys(json, chainPath) returns (string[] memory keys) {
                if (keys.length == 0) return;
                string[2] memory facetNames = [EIGEN_SERVICE_MANAGER_FACET, EIGEN_COVERAGE_PROVIDER_FACET];
                bool anyExist;
                for (uint256 k = 0; k < keys.length; k++) {
                    for (uint256 f = 0; f < 2; f++) {
                        if (keccak256(abi.encodePacked(keys[k])) == keccak256(abi.encodePacked(facetNames[f]))) {
                            anyExist = true;
                            break;
                        }
                    }
                    if (anyExist) break;
                }
                if (!anyExist) return;
                string[2] memory artifacts = [
                    "../../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol:EigenServiceManagerFacet",
                    "../../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol:EigenCoverageProviderFacet"
                ];
                bool allSameBytecode = true;
                for (uint256 f = 0; f < 2; f++) {
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
                            "Eigen provider facet deployments already exist for chain ",
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
                            "Eigen provider facet deployments already exist for chain ",
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
        string[2] memory names = [EIGEN_SERVICE_MANAGER_FACET, EIGEN_COVERAGE_PROVIDER_FACET];
        for (uint256 i = 0; i < 2; i++) {
            string memory jsonPath = string.concat(".", chainId, ".", names[i]);
            vm.writeJson(vm.toString(facetAddresses[i]), DEPLOYMENTS_PATH, jsonPath);
        }
        console.log("\nSaved Eigen provider facet deployments to", DEPLOYMENTS_PATH, "for chain", chainId);
    }
}
