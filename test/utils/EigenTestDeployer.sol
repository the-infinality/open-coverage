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
import {IDiamondLoupe} from "src/diamond/interfaces/IDiamondLoupe.sol";
import {IERC165} from "src/diamond/interfaces/IERC165.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";
import {EigenHelper, EigenAddressbook} from "../../utils/EigenHelper.sol";
import {CoverageAgent} from "src/CoverageAgent.sol";
import {UpgradeableBeacon} from "@openzeppelin-v5/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UniswapHelper, UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";

contract EigenTestDeployer is TestDeployer, EigenHelper, UniswapHelper {
    address public eigenOperatorInstance;
    uint32 public CALCULATION_INTERVAL_SECONDS;
    uint32 public MAX_REWARDS_DURATION;

    // *** Deployed Contracts *** //
    CoverageAgent coverageAgent;
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

        // Deploy all facets
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        eigenServiceManagerFacet = new EigenServiceManagerFacet();
        eigenCoverageProviderFacet = new EigenCoverageProviderFacet();
        assetPriceOracleAndSwapperFacet = new AssetPriceOracleAndSwapperFacet();

        // Prepare diamond cut with all facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](5);

        // DiamondCutFacet
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondCutSelectors()
        });

        // DiamondLoupeFacet
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getDiamondLoupeSelectors()
        });

        // EigenServiceManagerFacet
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(eigenServiceManagerFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEigenServiceManagerSelectors()
        });

        // EigenCoverageProviderFacet
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(eigenCoverageProviderFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getEigenCoverageProviderSelectors()
        });

        // AssetPriceOracleAndSwapperFacet
        cuts[4] = IDiamondCut.FacetCut({
            facetAddress: address(assetPriceOracleAndSwapperFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _getAssetPriceOracleAndSwapperSelectors()
        });

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
        coverageAgent = new CoverageAgent(address(this), USDC);

        // Deploy a instance for the upgradeable beacon proxies
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new EigenOperatorProxy()), address(this));
        eigenOperatorInstance = address(beacon);
    }

    function toRewardsInterval(uint256 timestamp) public view returns (uint32) {
        // casting to 'uint32' is safe because timestamp is always less than the length of the CALCULATION_INTERVAL_SECONDS
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(timestamp / CALCULATION_INTERVAL_SECONDS * CALCULATION_INTERVAL_SECONDS);
    }

    // ============ Selector Helper Functions ============ //

    function _getDiamondCutSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        return selectors;
    }

    function _getDiamondLoupeSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = IERC165.supportsInterface.selector;
        return selectors;
    }

    function _getEigenServiceManagerSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = IEigenServiceManager.eigenAddresses.selector;
        selectors[1] = IEigenServiceManager.registerOperator.selector;
        selectors[2] = IEigenServiceManager.setStrategyWhitelist.selector;
        selectors[3] = IEigenServiceManager.isStrategyWhitelisted.selector;
        selectors[4] = IEigenServiceManager.getOperatorSetId.selector;
        selectors[5] = IEigenServiceManager.coverageAllocated.selector;
        selectors[6] = IEigenServiceManager.captureRewards.selector;
        selectors[7] = IEigenServiceManager.submitOperatorReward.selector;
        selectors[8] = IEigenServiceManager.updateAVSMetadataURI.selector;
        selectors[9] = IEigenServiceManager.slashOperator.selector;
        selectors[10] = IEigenServiceManager.ensureAllocations.selector;
        selectors[11] = IEigenServiceManager.getAllocationedStrategies.selector;
        return selectors;
    }

    function _getEigenCoverageProviderSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = ICoverageProvider.onIsRegistered.selector;
        selectors[1] = ICoverageProvider.createPosition.selector;
        selectors[2] = ICoverageProvider.closePosition.selector;
        selectors[3] = ICoverageProvider.claimCoverage.selector;
        selectors[4] = ICoverageProvider.liquidateClaim.selector;
        selectors[5] = ICoverageProvider.completeClaims.selector;
        selectors[6] = ICoverageProvider.slashClaims.selector;
        selectors[7] = ICoverageProvider.completeSlash.selector;
        selectors[8] = ICoverageProvider.position.selector;
        selectors[9] = ICoverageProvider.positionMaxAmount.selector;
        selectors[10] = ICoverageProvider.claim.selector;
        selectors[11] = ICoverageProvider.claimDeficit.selector;
        return selectors;
    }

    function _getAssetPriceOracleAndSwapperSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = IAssetPriceOracleAndSwapper.register.selector;
        selectors[1] = IAssetPriceOracleAndSwapper.swapForOutput.selector;
        selectors[2] = IAssetPriceOracleAndSwapper.swapForInput.selector;
        selectors[3] = IAssetPriceOracleAndSwapper.swapForOutputQuote.selector;
        selectors[4] = IAssetPriceOracleAndSwapper.swapForInputQuote.selector;
        selectors[5] = IAssetPriceOracleAndSwapper.assetPair.selector;
        selectors[6] = IAssetPriceOracleAndSwapper.getQuote.selector;
        return selectors;
    }
}
