// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {EigenHelper, EigenAddressbook} from "../EigenHelper.sol";
import {UniswapHelper, UniswapAddressbook} from "../UniswapHelper.sol";
import {EigenCoverageDiamond} from "../../src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {EigenAddresses} from "../../src/providers/eigenlayer/Types.sol";
import {DiamondFacetsDeployer} from "./DiamondFacetsDeployer.sol";
import {EigenFacetsDeployer} from "./EigenFacetsDeployer.sol";
import {AssetPriceOracleAndSwapperFacetDeployer} from "./AssetPriceOracleAndSwapperFacetDeployer.sol";
import {UniswapV3SwapperEngine} from "../../src/swapper-engines/UniswapV3SwapperEngine.sol";
import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/diamond/facets/OwnershipFacet.sol";
import {EigenServiceManagerFacet} from "../../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "../../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {AssetPriceOracleAndSwapperFacet} from "../../src/facets/AssetPriceOracleAndSwapperFacet.sol";

/// @title DeployerHelperScript
/// @notice Abstract base for deployment scripts with shared config save, broadcast guard, and per-contract deploy helpers.
abstract contract DeployerHelperScript is Script, EigenHelper, UniswapHelper {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    string constant DIAMOND_CUT_FACET = "DiamondCutFacet";
    string constant DIAMOND_LOUPE_FACET = "DiamondLoupeFacet";
    string constant OWNERSHIP_FACET = "OwnershipFacet";
    string constant EIGEN_SERVICE_MANAGER_FACET = "EigenServiceManagerFacet";
    string constant EIGEN_COVERAGE_PROVIDER_FACET = "EigenCoverageProviderFacet";
    string constant ASSET_PRICE_ORACLE_AND_SWAPPER_FACET = "AssetPriceOracleAndSwapperFacet";
    string constant UNISWAP_V3_SWAPPER_ENGINE = "UniswapV3SwapperEngine";
    string constant EIGEN_COVERAGE_DIAMOND = "EigenCoverageDiamond";

    // -------------------------------------------------------------------------
    // Generic config helpers
    // -------------------------------------------------------------------------

    function _isBroadcasting() internal view returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.ScriptBroadcast);
    }

    function _saveDeployment(string memory name, address addr) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory jsonPath = string.concat(".", chainId, ".", name);
        vm.writeJson(vm.toString(addr), DEPLOYMENTS_PATH, jsonPath);
    }

    function _saveDeployments(string[] memory names, address[] memory addrs) internal {
        require(names.length == addrs.length, "DeployerHelperScript: length mismatch");
        for (uint256 i = 0; i < names.length; i++) {
            _saveDeployment(names[i], addrs[i]);
        }
    }

    function _saveIfBroadcasting(string memory name, address addr) internal {
        if (!_isBroadcasting()) return;
        _saveDeployment(name, addr);
        console.log("Saved deployment:", name, addr);
    }

    function _saveIfBroadcasting(string[] memory names, address[] memory addrs) internal {
        if (!_isBroadcasting()) return;
        _saveDeployments(names, addrs);
        console.log("Saved deployments to", DEPLOYMENTS_PATH);
    }

    // -------------------------------------------------------------------------
    // Per-contract deployment helpers (call within vm.startBroadcast / stopBroadcast)
    // -------------------------------------------------------------------------

    function _deployDiamondFacets()
        internal
        returns (address diamondCut, address diamondLoupe, address ownership)
    {
        (
            DiamondCutFacet diamondCutFacet,
            DiamondLoupeFacet diamondLoupeFacet,
            OwnershipFacet ownershipFacet
        ) = DiamondFacetsDeployer.deployDiamondFacets();
        diamondCut = address(diamondCutFacet);
        diamondLoupe = address(diamondLoupeFacet);
        ownership = address(ownershipFacet);
    }

    function _deployEigenProviderFacets()
        internal
        returns (address eigenServiceManager, address eigenCoverageProvider)
    {
        (
            EigenServiceManagerFacet eigenServiceManagerFacet,
            EigenCoverageProviderFacet eigenCoverageProviderFacet
        ) = EigenFacetsDeployer.deployEigenFacets();
        eigenServiceManager = address(eigenServiceManagerFacet);
        eigenCoverageProvider = address(eigenCoverageProviderFacet);
    }

    function _deployAssetPriceOracleAndSwapperFacet() internal returns (address facet) {
        AssetPriceOracleAndSwapperFacet f =
            AssetPriceOracleAndSwapperFacetDeployer.deployAssetPriceOracleAndSwapperFacet();
        facet = address(f);
    }

    function _deployUniswapV3SwapperEngine(
        address universalRouter,
        address permit2,
        address quoter
    ) internal returns (address) {
        UniswapV3SwapperEngine engine = new UniswapV3SwapperEngine(universalRouter, permit2, quoter);
        return address(engine);
    }

    function _deployEigenCoverageDiamond(
        IDiamondCut.FacetCut[] memory cuts,
        EigenCoverageDiamond.DiamondArgs memory args
    ) internal returns (address) {
        EigenCoverageDiamond diamond = new EigenCoverageDiamond(cuts, args);
        return address(diamond);
    }

    // -------------------------------------------------------------------------
    // Facet cut and args builders
    // -------------------------------------------------------------------------

    function _buildAllFacetCuts(
        address diamondCut,
        address diamondLoupe,
        address ownership,
        address eigenServiceManager,
        address eigenCoverageProvider,
        address assetPriceOracleSwapper
    ) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](6);
        IDiamondCut.FacetCut[] memory d =
            DiamondFacetsDeployer.getDiamondFacetCutsFromAddresses(diamondCut, diamondLoupe, ownership);
        IDiamondCut.FacetCut[] memory e =
            EigenFacetsDeployer.getEigenFacetCutsFromAddresses(eigenServiceManager, eigenCoverageProvider);
        IDiamondCut.FacetCut memory a =
            AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperFacetCutFromAddress(
                assetPriceOracleSwapper
            );
        cuts[0] = d[0];
        cuts[1] = d[1];
        cuts[2] = d[2];
        cuts[3] = e[0];
        cuts[4] = e[1];
        cuts[5] = a;
    }

    function _buildDiamondArgs(
        address owner,
        string memory metadataURI
    ) internal view returns (EigenCoverageDiamond.DiamondArgs memory) {
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
}
