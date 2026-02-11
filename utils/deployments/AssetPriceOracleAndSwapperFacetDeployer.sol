// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetPriceOracleAndSwapperFacet} from "src/facets/AssetPriceOracleAndSwapperFacet.sol";
import {IDiamondCut} from "src/diamond/interfaces/IDiamondCut.sol";
import {IAssetPriceOracleAndSwapper} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";

/// @title AssetPriceOracleAndSwapperFacetDeployer
/// @notice Helper contract for deploying AssetPriceOracleAndSwapperFacet
/// @dev This facet provides asset price oracle and swapping functionality
library AssetPriceOracleAndSwapperFacetDeployer {
    /// @notice Deploys AssetPriceOracleAndSwapperFacet
    /// @return assetPriceOracleAndSwapperFacet The deployed AssetPriceOracleAndSwapperFacet instance
    function deployAssetPriceOracleAndSwapperFacet()
        internal
        returns (AssetPriceOracleAndSwapperFacet assetPriceOracleAndSwapperFacet)
    {
        assetPriceOracleAndSwapperFacet = new AssetPriceOracleAndSwapperFacet();
    }

    /// @notice Creates facet cut for AssetPriceOracleAndSwapperFacet
    /// @param assetPriceOracleAndSwapperFacet The deployed AssetPriceOracleAndSwapperFacet instance
    /// @return cut Facet cut for AssetPriceOracleAndSwapperFacet
    function getAssetPriceOracleAndSwapperFacetCut(
        AssetPriceOracleAndSwapperFacet assetPriceOracleAndSwapperFacet
    ) internal pure returns (IDiamondCut.FacetCut memory cut) {
        return getAssetPriceOracleAndSwapperFacetCutFromAddress(address(assetPriceOracleAndSwapperFacet));
    }

    /// @notice Creates facet cut from pre-deployed facet address (e.g. from deployments.json)
    /// @param facetAddress Address of deployed AssetPriceOracleAndSwapperFacet
    /// @return cut Facet cut for AssetPriceOracleAndSwapperFacet
    function getAssetPriceOracleAndSwapperFacetCutFromAddress(address facetAddress)
        internal
        pure
        returns (IDiamondCut.FacetCut memory cut)
    {
        cut = IDiamondCut.FacetCut({
            facetAddress: facetAddress,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getAssetPriceOracleAndSwapperSelectors()
        });
    }

    /// @notice Gets function selectors for AssetPriceOracleAndSwapperFacet
    /// @return selectors Array of function selectors
    function getAssetPriceOracleAndSwapperSelectors()
        internal
        pure
        returns (bytes4[] memory selectors)
    {
        selectors = new bytes4[](9);
        selectors[0] = IAssetPriceOracleAndSwapper.register.selector;
        selectors[1] = IAssetPriceOracleAndSwapper.swapForOutput.selector;
        selectors[2] = IAssetPriceOracleAndSwapper.swapForInput.selector;
        selectors[3] = IAssetPriceOracleAndSwapper.swapForOutputQuote.selector;
        selectors[4] = IAssetPriceOracleAndSwapper.swapForInputQuote.selector;
        selectors[5] = IAssetPriceOracleAndSwapper.assetPair.selector;
        selectors[6] = IAssetPriceOracleAndSwapper.getQuote.selector;
        selectors[7] = IAssetPriceOracleAndSwapper.setSwapSlippage.selector;
        selectors[8] = IAssetPriceOracleAndSwapper.swapSlippage.selector;
    }
}

