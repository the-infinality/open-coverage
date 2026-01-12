// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EigenServiceManagerFacet} from "../../src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "../../src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamond} from "../../src/diamond/interfaces/IDiamond.sol";
import {IEigenServiceManager} from "../../src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {ICoverageProvider} from "../../src/interfaces/ICoverageProvider.sol";

/// @title EigenFacetsDeployer
/// @notice Helper contract for deploying Eigen-specific facets
/// @dev Deploys EigenServiceManagerFacet and EigenCoverageProviderFacet
library EigenFacetsDeployer {
    /// @notice Deploys EigenServiceManagerFacet and EigenCoverageProviderFacet
    /// @return eigenServiceManagerFacet The deployed EigenServiceManagerFacet instance
    /// @return eigenCoverageProviderFacet The deployed EigenCoverageProviderFacet instance
    function deployEigenFacets()
        internal
        returns (
            EigenServiceManagerFacet eigenServiceManagerFacet,
            EigenCoverageProviderFacet eigenCoverageProviderFacet
        )
    {
        eigenServiceManagerFacet = new EigenServiceManagerFacet();
        eigenCoverageProviderFacet = new EigenCoverageProviderFacet();
    }

    /// @notice Creates facet cuts for Eigen-specific facets
    /// @param eigenServiceManagerFacet The deployed EigenServiceManagerFacet instance
    /// @param eigenCoverageProviderFacet The deployed EigenCoverageProviderFacet instance
    /// @return cuts Array of facet cuts for Eigen facets
    function getEigenFacetCuts(
        EigenServiceManagerFacet eigenServiceManagerFacet,
        EigenCoverageProviderFacet eigenCoverageProviderFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](2);

        // EigenServiceManagerFacet
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(eigenServiceManagerFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getEigenServiceManagerSelectors()
        });

        // EigenCoverageProviderFacet
        cuts[1] = IDiamond.FacetCut({
            facetAddress: address(eigenCoverageProviderFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getEigenCoverageProviderSelectors()
        });
    }

    /// @notice Gets function selectors for EigenServiceManagerFacet
    /// @return selectors Array of function selectors
    function getEigenServiceManagerSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
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
    }

    /// @notice Gets function selectors for EigenCoverageProviderFacet
    /// @return selectors Array of function selectors
    function getEigenCoverageProviderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
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
    }
}

