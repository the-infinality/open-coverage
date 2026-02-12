// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EigenServiceManagerFacet} from "src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol";
import {EigenCoverageProviderFacet} from "src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IEigenServiceManager} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {ICoverageProvider} from "src/interfaces/ICoverageProvider.sol";

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
        return getEigenFacetCutsFromAddresses(
            address(eigenServiceManagerFacet),
            address(eigenCoverageProviderFacet)
        );
    }

    /// @notice Creates facet cuts from pre-deployed facet addresses (e.g. from deployments.json)
    /// @param eigenServiceManagerFacetAddress Address of deployed EigenServiceManagerFacet
    /// @param eigenCoverageProviderFacetAddress Address of deployed EigenCoverageProviderFacet
    /// @return cuts Array of facet cuts for Eigen facets
    function getEigenFacetCutsFromAddresses(
        address eigenServiceManagerFacetAddress,
        address eigenCoverageProviderFacetAddress
    ) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](2);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: eigenServiceManagerFacetAddress,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getEigenServiceManagerSelectors()
        });
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: eigenCoverageProviderFacetAddress,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getEigenCoverageProviderSelectors()
        });
    }

    /// @notice Gets function selectors for EigenServiceManagerFacet
    /// @return selectors Array of function selectors
    function getEigenServiceManagerSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = IEigenServiceManager.eigenAddresses.selector;
        selectors[1] = IEigenServiceManager.registerOperator.selector;
        selectors[2] = IEigenServiceManager.setStrategyWhitelist.selector;
        selectors[3] = IEigenServiceManager.isStrategyWhitelisted.selector;
        selectors[4] = IEigenServiceManager.whitelistedStrategies.selector;
        selectors[5] = IEigenServiceManager.getOperatorSetId.selector;
        selectors[6] = IEigenServiceManager.coverageAllocated.selector;
        selectors[7] = IEigenServiceManager.captureRewards.selector;
        selectors[8] = IEigenServiceManager.submitOperatorReward.selector;
        selectors[9] = IEigenServiceManager.updateAVSMetadataURI.selector;
        selectors[10] = IEigenServiceManager.slashOperator.selector;
        selectors[11] = IEigenServiceManager.ensureAllocations.selector;
        selectors[12] = IEigenServiceManager.getAllocationedStrategies.selector;
        selectors[13] = IEigenServiceManager.setCoverageThreshold.selector;
        selectors[14] = IEigenServiceManager.getCoverageThreshold.selector;
    }

    /// @notice Gets function selectors for EigenCoverageProviderFacet
    /// @return selectors Array of function selectors
    function getEigenCoverageProviderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](17);
        selectors[0] = ICoverageProvider.onIsRegistered.selector;
        selectors[1] = ICoverageProvider.createPosition.selector;
        selectors[2] = ICoverageProvider.closePosition.selector;
        selectors[3] = ICoverageProvider.issueClaim.selector;
        selectors[4] = ICoverageProvider.liquidateClaim.selector;
        selectors[5] = ICoverageProvider.closeClaim.selector;
        selectors[6] = ICoverageProvider.reserveClaim.selector;
        selectors[7] = ICoverageProvider.convertReservedClaim.selector;
        selectors[8] = ICoverageProvider.slashClaims.selector;
        selectors[9] = ICoverageProvider.completeSlash.selector;
        selectors[10] = ICoverageProvider.repaySlashedClaim.selector;
        selectors[11] = ICoverageProvider.position.selector;
        selectors[12] = ICoverageProvider.positionMaxAmount.selector;
        selectors[13] = ICoverageProvider.claim.selector;
        selectors[14] = ICoverageProvider.claimBacking.selector;
        selectors[15] = ICoverageProvider.providerTypeId.selector;
        selectors[16] = ICoverageProvider.claimTotalSlashAmount.selector;
    }
}

