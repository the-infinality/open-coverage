// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamond} from "../../src/diamond/interfaces/IDiamond.sol";
import {IDiamondLoupe} from "../../src/diamond/interfaces/IDiamondLoupe.sol";
import {IERC165} from "../../src/diamond/interfaces/IERC165.sol";

/// @title DiamondFacetsDeployer
/// @notice Helper contract for deploying diamond core facets (DiamondCutFacet and DiamondLoupeFacet)
/// @dev These facets are reusable across different diamond implementations
library DiamondFacetsDeployer {
    /// @notice Deploys DiamondCutFacet and DiamondLoupeFacet
    /// @return diamondCutFacet The deployed DiamondCutFacet instance
    /// @return diamondLoupeFacet The deployed DiamondLoupeFacet instance
    function deployDiamondFacets()
        internal
        returns (DiamondCutFacet diamondCutFacet, DiamondLoupeFacet diamondLoupeFacet)
    {
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
    }

    /// @notice Creates facet cuts for DiamondCutFacet and DiamondLoupeFacet
    /// @param diamondCutFacet The deployed DiamondCutFacet instance
    /// @param diamondLoupeFacet The deployed DiamondLoupeFacet instance
    /// @return cuts Array of facet cuts for diamond core facets
    function getDiamondFacetCuts(
        DiamondCutFacet diamondCutFacet,
        DiamondLoupeFacet diamondLoupeFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](2);

        // DiamondCutFacet
        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getDiamondCutSelectors()
        });

        // DiamondLoupeFacet
        cuts[1] = IDiamond.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: getDiamondLoupeSelectors()
        });
    }

    /// @notice Gets function selectors for DiamondCutFacet
    /// @return selectors Array of function selectors
    function getDiamondCutSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
    }

    /// @notice Gets function selectors for DiamondLoupeFacet
    /// @return selectors Array of function selectors
    function getDiamondLoupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = IERC165.supportsInterface.selector;
    }
}

