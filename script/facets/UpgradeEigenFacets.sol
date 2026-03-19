// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/diamond/interfaces/IDiamondLoupe.sol";
import {EigenFacetsDeployer} from "../../utils/deployments/EigenFacetsDeployer.sol";

/// @notice Shared logic for Eigen facet upgrade scripts (read from deployments.json, verify).
abstract contract UpgradeEigenFacetsBase is Script {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    function _getFacetAddressFromDeployments(string memory facetKey) internal view returns (address) {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(DEPLOYMENTS_PATH);
        string memory chainPath = string.concat(".", vm.toString(block.chainid), ".", facetKey);
        try vm.parseJsonAddress(json, chainPath) returns (address a) {
            require(a != address(0), "UpgradeEigenFacets: facet address not found in deployments.json for this chain");
            return a;
        } catch {
            revert("UpgradeEigenFacets: facet not found in config/deployments.json for this chain");
        }
    }

    function _verifyFacet(address diamondAddress, bytes4 selector, address expectedFacet) internal view {
        address actual = IDiamondLoupe(diamondAddress).facetAddress(selector);
        require(actual == expectedFacet, "UpgradeEigenFacets: verification failed");
    }
}

/// @title UpgradeCoverageProvider
/// @notice Script to upgrade EigenCoverageProviderFacet on an existing EigenCoverageDiamond.
/// @dev Reads target facet address from config/deployments.json (EigenCoverageProviderFacet) for the current chain. Prompts for the diamond address.
///
/// Usage:
///   forge script script/facets/UpgradeEigenFacets.sol:UpgradeCoverageProvider \
///     --rpc-url <rpc> --broadcast --private-key <key>
contract UpgradeCoverageProvider is UpgradeEigenFacetsBase {
    function run() public {
        address diamondAddress = vm.promptAddress("EigenCoverageDiamond address to upgrade");
        address newFacet = _getFacetAddressFromDeployments("EigenCoverageProviderFacet");
        console.log("Upgrading EigenCoverageProviderFacet on diamond", diamondAddress, "to", newFacet);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: newFacet,
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: EigenFacetsDeployer.getEigenCoverageProviderSelectors()
        });
        vm.startBroadcast();
        IDiamondCut(diamondAddress).diamondCut(cuts, address(0), "");
        vm.stopBroadcast();
        _verifyFacet(diamondAddress, EigenFacetsDeployer.getEigenCoverageProviderSelectors()[0], newFacet);
        console.log("EigenCoverageProviderFacet upgrade complete.");
    }
}

/// @title UpgradeServiceManager
/// @notice Script to upgrade EigenServiceManagerFacet on an existing EigenCoverageDiamond.
/// @dev Reads target facet address from config/deployments.json (EigenServiceManagerFacet) for the current chain. Prompts for the diamond address.
///
/// Usage:
///   forge script script/facets/UpgradeEigenFacets.sol:UpgradeServiceManager \
///     --rpc-url <rpc> --broadcast --private-key <key>
contract UpgradeServiceManager is UpgradeEigenFacetsBase {
    function run() public {
        address diamondAddress = vm.promptAddress("EigenCoverageDiamond address to upgrade");
        address newFacet = _getFacetAddressFromDeployments("EigenServiceManagerFacet");
        console.log("Upgrading EigenServiceManagerFacet on diamond", diamondAddress, "to", newFacet);
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: newFacet,
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: EigenFacetsDeployer.getEigenServiceManagerSelectors()
        });
        vm.startBroadcast();
        IDiamondCut(diamondAddress).diamondCut(cuts, address(0), "");
        vm.stopBroadcast();
        _verifyFacet(diamondAddress, EigenFacetsDeployer.getEigenServiceManagerSelectors()[0], newFacet);
        console.log("EigenServiceManagerFacet upgrade complete.");
    }
}
