# AssetPriceOracleAndSwapper

## Links

- [Interface](../../src/interfaces/IAssetPriceOracleAndSwapper.sol)
- [Implementation](../../src/mixins/AssetPriceOracleAndSwapper.sol)
- [Diamond Facet](../../src/facets/AssetPriceOracleAndSwapperFacet.sol)

## Overview

The AssetPriceOracleAndSwapper contract is a utility contract that allows for the pricing of assets and the swapping of assets. It is used to price in risk coverage for the specific assets since the asset providing coverage is rarely the same as the asset being covered. The contract always enables a two tier pricing system where a price oracle implementation can be used to verify the quote from the swapper.

## Specification

### register

Registers a new asset pair for pricing and swapping.

```solidity
function register(AssetPair calldata _assetPair) external;
```

### swapForOutput

Swaps an exact amount of output tokens for an input amount of tokens based on slippage.

```solidity
function swapForOutput(uint256 amountOut, address assetA, address assetB) external;
```

### swapForInput

Swaps an exact amount of input tokens for an output amount of tokens based on slippage.

```solidity
function swapForInput(uint256 amountIn, address assetA, address assetB) external;
```

### setSwapSlippage

Sets the swap slippage for the asset pair.

```solidity
function setSwapSlippage(uint16 swapSlippage) external;
```

### assetPair

Gets the asset pair configuration for two assets.

```solidity
function assetPair(address assetA, address assetB) external view returns (AssetPair memory);
```

### swapSlippage

Gets the swap slippage for the asset pair.

```solidity
function swapSlippage() external view returns (uint16);
```

### getQuote

Gets a price quote for an asset pair.

```solidity
function getQuote(uint256 amountIn, address assetA, address assetB) external view returns (uint256 quote, bool verified);
```

### swapForOutputQuote

Gets the maximum amount of `assetB` tokens that can be spent to receive `amountOut` of `assetA` based on slippage.

```solidity
function swapForOutputQuote(uint256 amountOut, address assetA, address assetB) external view returns (uint256 maxAmountIn);
```

### swapForInputQuote

Gets the minimum amount of `assetA` tokens that can be received for `amountIn` of `assetB` based on slippage.

```solidity
function swapForInputQuote(uint256 amountIn, address assetA, address assetB) external view returns (uint256 minAmountOut);
```

### Events

| Event | Description |
|---|---|
| `AssetPairRegistered(address assetA, address assetB)` | Emitted when a new asset pair is registered for pricing and swapping. |

### Errors

| Error | Description |
|---|---|
| `PriceMismatch()` | The price quote from the swapper does not match the oracle within the accepted accuracy. |
| `SwapFailed()` | The swap operation failed. |
| `InvalidPoolInfo()` | The provided pool info for the swap engine is invalid. |
| `AssetPairNotRegistered()` | The requested asset pair has not been registered. |
| `PriceOracleRequired()` | A price oracle is required for the selected price strategy but was not provided. |
| `InvalidAssetPair()` | The provided asset pair configuration is invalid. |
| `InvalidSwapperAccuracy()` | The provided swapper accuracy value is invalid. |
| `InvalidSwapSlippage()` | The provided swap slippage value is invalid. |
