// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenHelper, EigenAddressbook} from "../utils/EigenHelper.sol";
import {UniswapHelper, UniswapAddressbook} from "../utils/UniswapHelper.sol";
import {EigenCoverageDiamond} from "../src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {EigenAddresses} from "../src/providers/eigenlayer/Types.sol";
import {DiamondFacetsDeployer} from "../utils/deployments/DiamondFacetsDeployer.sol";
import {EigenFacetsDeployer} from "../utils/deployments/EigenFacetsDeployer.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";

/// @title DeployEigenProvider
/// @notice Script to deploy EigenCoverageDiamond using pre-deployed facet addresses from config/deployments.json
/// @dev Requires all six facets to be deployed and recorded for the current chain. See Facet Deployment.md.
contract DeployEigenProvider is Script, EigenHelper, UniswapHelper {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    string constant DIAMOND_CUT_FACET = "DiamondCutFacet";
    string constant DIAMOND_LOUPE_FACET = "DiamondLoupeFacet";
    string constant OWNERSHIP_FACET = "OwnershipFacet";
    string constant EIGEN_SERVICE_MANAGER_FACET = "EigenServiceManagerFacet";
    string constant EIGEN_COVERAGE_PROVIDER_FACET = "EigenCoverageProviderFacet";
    string constant ASSET_PRICE_ORACLE_AND_SWAPPER_FACET = "AssetPriceOracleAndSwapperFacet";

    function run() public returns (address eigenCoverageDiamondAddress) {
        IDiamondCut.FacetCut[] memory cuts = _getFacetCutsFromDeployments();

        vm.startBroadcast();

        address owner = msg.sender;
        string memory metadataURI = vm.envOr("AVS_METADATA_URI", string("https://coverage.example.com/metadata.json"));

        console.log("Deploying EigenCoverageDiamond...");
        console.log("Owner:", owner);
        console.log("Metadata URI:", metadataURI);

        EigenCoverageDiamond.DiamondArgs memory args = _prepareDiamondArgs(owner, metadataURI);
        EigenCoverageDiamond eigenCoverageDiamond = new EigenCoverageDiamond(cuts, args);
        eigenCoverageDiamondAddress = address(eigenCoverageDiamond);

        _logDeploymentSummary(eigenCoverageDiamondAddress, cuts);

        vm.stopBroadcast();

        return eigenCoverageDiamondAddress;
    }

    /// @notice Loads facet addresses from deployments.json and builds facet cuts. Reverts with missing list if any required facet is not deployed.
    function _getFacetCutsFromDeployments() internal view returns (IDiamondCut.FacetCut[] memory cuts) {
        address[6] memory addrs = _getRequiredFacetAddresses();
        cuts = new IDiamondCut.FacetCut[](6);
        IDiamondCut.FacetCut[] memory d =
            DiamondFacetsDeployer.getDiamondFacetCutsFromAddresses(addrs[0], addrs[1], addrs[2]);
        IDiamondCut.FacetCut[] memory e = EigenFacetsDeployer.getEigenFacetCutsFromAddresses(addrs[3], addrs[4]);
        IDiamondCut.FacetCut memory a =
            AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperFacetCutFromAddress(addrs[5]);
        cuts[0] = d[0];
        cuts[1] = d[1];
        cuts[2] = d[2];
        cuts[3] = e[0];
        cuts[4] = e[1];
        cuts[5] = a;
    }

    /// @notice Reads deployments.json and returns the six required facet addresses for the current chain. Reverts listing any missing.
    function _getRequiredFacetAddresses() internal view returns (address[6] memory addrs) {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(DEPLOYMENTS_PATH);
        string memory chainId = vm.toString(block.chainid);
        string memory chainPath = string.concat(".", chainId);

        string[6] memory requiredNames = [
            DIAMOND_CUT_FACET,
            DIAMOND_LOUPE_FACET,
            OWNERSHIP_FACET,
            EIGEN_SERVICE_MANAGER_FACET,
            EIGEN_COVERAGE_PROVIDER_FACET,
            ASSET_PRICE_ORACLE_AND_SWAPPER_FACET
        ];

        string[] memory keys;
        try vm.parseJsonKeys(json, chainPath) returns (string[] memory k) {
            keys = k;
        } catch {
            _revertMissing(requiredNames, chainId);
        }

        bool anyMissing = false;
        for (uint256 r = 0; r < 6; r++) {
            bool found = false;
            for (uint256 i = 0; i < keys.length; i++) {
                if (keccak256(abi.encodePacked(keys[i])) == keccak256(abi.encodePacked(requiredNames[r]))) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                console.log("Missing facet deployment:", requiredNames[r]);
                anyMissing = true;
            }
        }
        require(!anyMissing, "Deploy required facets first. See Facet Deployment.md");

        addrs[0] = vm.parseJsonAddress(json, string.concat(chainPath, ".", DIAMOND_CUT_FACET));
        addrs[1] = vm.parseJsonAddress(json, string.concat(chainPath, ".", DIAMOND_LOUPE_FACET));
        addrs[2] = vm.parseJsonAddress(json, string.concat(chainPath, ".", OWNERSHIP_FACET));
        addrs[3] = vm.parseJsonAddress(json, string.concat(chainPath, ".", EIGEN_SERVICE_MANAGER_FACET));
        addrs[4] = vm.parseJsonAddress(json, string.concat(chainPath, ".", EIGEN_COVERAGE_PROVIDER_FACET));
        addrs[5] = vm.parseJsonAddress(json, string.concat(chainPath, ".", ASSET_PRICE_ORACLE_AND_SWAPPER_FACET));
    }

    function _revertMissing(string[6] memory requiredNames, string memory chainId) internal pure {
        console.log("Missing required facet deployments for chain", chainId);
        for (uint256 r = 0; r < 6; r++) {
            console.log(" -", requiredNames[r]);
        }
        revert("Deploy required facets first. See Facet Deployment.md");
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
