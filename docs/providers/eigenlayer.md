# Eigenlayer

## Links

- [Website](https://eigen.layer/)
- [X](https://x.com/eigen_labs)

## Implementation

The Eigenlayer implementation is a EIP-2535 Diamond Standard implementation that utilises the following facets:

- [EigenCoverageProviderFacet](src/providers/eigenlayer/facets/EigenCoverageProviderFacet.sol)
- [EigenServiceManagerFacet](src/providers/eigenlayer/facets/EigenServiceManagerFacet.sol)
- [AssetPriceOracleAndSwapperFacet](src/facets/AssetPriceOracleAndSwapperFacet.sol)


### EigenCoverageProviderFacet

Includes the core coverage provider logic as per the [ICoverageProvider](src/interfaces/ICoverageProvider.sol) interface.

### EigenServiceManagerFacet

Includes the core Eigenlayer coordination logic as per the [IEigenServiceManager](src/providers/eigenlayer/interfaces/IEigenServiceManager.sol) interface.