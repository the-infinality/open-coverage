// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "./TestDeployer.sol";
import {EigenAddresses} from "src/providers/eigenlayer/Types.sol";
import {EigenCoverageDiamond} from "src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {EigenServiceManagerFacet} from "src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {AssetPriceOracleAndSwapperFacet} from "src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {DiamondCutFacet} from "src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {EigenHelper, EigenAddressbook} from "../../utils/EigenHelper.sol";
import {ExampleCoverageAgent} from "src/ExampleCoverageAgent.sol";
import {UniswapHelper, UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {DiamondFacetsDeployer} from "../../utils/deployments/DiamondFacetsDeployer.sol";
import {EigenFacetsDeployer} from "../../utils/deployments/EigenFacetsDeployer.sol";
import {
    AssetPriceOracleAndSwapperFacetDeployer
} from "../../utils/deployments/AssetPriceOracleAndSwapperFacetDeployer.sol";

contract EigenTestDeployer is TestDeployer, EigenHelper, UniswapHelper {
    address public eigenOperatorInstance;
    uint32 public CALCULATION_INTERVAL_SECONDS;
    uint32 public MAX_REWARDS_DURATION;

    // *** Deployed Contracts *** //
    ExampleCoverageAgent coverageAgent;
    EigenCoverageDiamond eigenCoverageDiamond;

    // Facets
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    EigenServiceManagerFacet eigenServiceManagerFacet;
    EigenCoverageProviderFacet eigenCoverageProviderFacet;
    AssetPriceOracleAndSwapperFacet assetPriceOracleAndSwapperFacet;

    function setUp() public virtual override {
        super.setUp();

        EigenAddressbook memory eigenAddressBook = _getAddressBook();
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        IRewardsCoordinator rewardsCoordinator = _getRewardsCoordinator();
        CALCULATION_INTERVAL_SECONDS = rewardsCoordinator.CALCULATION_INTERVAL_SECONDS();
        MAX_REWARDS_DURATION = rewardsCoordinator.MAX_REWARDS_DURATION();

        // Deploy facets using deployment helper libraries
        (diamondCutFacet, diamondLoupeFacet) = DiamondFacetsDeployer.deployDiamondFacets();
        (eigenServiceManagerFacet, eigenCoverageProviderFacet) = EigenFacetsDeployer.deployEigenFacets();
        assetPriceOracleAndSwapperFacet =
            AssetPriceOracleAndSwapperFacetDeployer.deployAssetPriceOracleAndSwapperFacet();

        // Get facet cuts from deployment helper libraries
        IDiamondCut.FacetCut[] memory diamondCuts =
            DiamondFacetsDeployer.getDiamondFacetCuts(diamondCutFacet, diamondLoupeFacet);
        IDiamondCut.FacetCut[] memory eigenCuts =
            EigenFacetsDeployer.getEigenFacetCuts(eigenServiceManagerFacet, eigenCoverageProviderFacet);
        IDiamondCut.FacetCut memory assetPriceOracleAndSwapperCut =
            AssetPriceOracleAndSwapperFacetDeployer.getAssetPriceOracleAndSwapperFacetCut(
                assetPriceOracleAndSwapperFacet
            );

        // Combine all facet cuts (5 facets total)
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](5);
        cuts[0] = diamondCuts[0]; // DiamondCutFacet
        cuts[1] = diamondCuts[1]; // DiamondLoupeFacet
        cuts[2] = eigenCuts[0]; // EigenServiceManagerFacet
        cuts[3] = eigenCuts[1]; // EigenCoverageProviderFacet
        cuts[4] = assetPriceOracleAndSwapperCut; // AssetPriceOracleAndSwapperFacet

        // Deploy diamond with all facets
        EigenCoverageDiamond.DiamondArgs memory args = EigenCoverageDiamond.DiamondArgs({
            owner: owner,
            eigenAddresses: EigenAddresses({
                allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
                delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
                strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
                rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
                permissionController: eigenAddressBook.eigenAddresses.permissionController
            }),
            metadataURI: "https://coverage.example.com/metadata.json",
            universalRouter: uniswapAddressBook.uniswapAddresses.universalRouter,
            permit2: uniswapAddressBook.uniswapAddresses.permit2
        });

        eigenCoverageDiamond = new EigenCoverageDiamond(cuts, args);

        // Deploy coverage agent and allow this address to be the operator
        coverageAgent = new ExampleCoverageAgent(address(this), USDC);

        // Set eigenOperatorInstance to address(0) since we deploy directly now (no beacon pattern)
        eigenOperatorInstance = address(0);
    }

    function toRewardsInterval(uint256 timestamp) public view returns (uint32) {
        // casting to 'uint32' is safe because timestamp is always less than the length of the CALCULATION_INTERVAL_SECONDS
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(timestamp / CALCULATION_INTERVAL_SECONDS * CALCULATION_INTERVAL_SECONDS);
    }
}
