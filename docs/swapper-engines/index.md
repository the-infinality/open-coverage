# Swapper Engines

- [Interface](src/interfaces/ISwapperEngine.sol)

Swapper Engines are utlised by the AssetPriceOracleAndSwapper contract to perform the actual swapping of assets. These contracts are designed to be modular and therefore can be used with any protocol that is designed to handle the swapping of assets such as Uniswap, Maverick, etc.

## How it works

The Swapper Engines are to be used by any contract that needs to perform a swap of assets. The contract will need to implement the ISwapperEngine interface and then delegatecall to the swapper engine to perform swaps.

## Specification

### swapForInput

Swaps with an exact amount of input tokens with a minimum amount of output tokens. This function is inspired by the Uniswap V3 `exactInput` function.

```solidity
function swapForInput(bytes memory poolInfo, uint256 amountIn, uint256 amountOutMin, address base, address swap)
    external
    returns (uint256 amountOut);
```

### swapForOutput

Swaps to an exact amount of output tokens with a maximum amount of input tokens. This function is inspired by the Uniswap V3 `exactOutput` function.

```solidity
function swapForOutput(bytes memory poolInfo, uint256 amountOut, uint256 amountInMax, address base, address swap)
    external
    returns (uint256 amountIn);
```

### getQuote

Quotes the amount of `base` that is equivalent to `amountIn` of `quote` similar to the IPriceOracle interface standard.

```solidity
function getQuote(bytes memory poolInfo, uint256 amountIn, address base, address quote)
    external
    view
    returns (uint256 amountOut);
```

### onInit

Called when the swapper engine is initialized. Can be used for tasks such as approving the tokens to be spent by the swapper engine.

```solidity
function onInit(bytes memory poolInfo) external;
```

## Existing Swapper Engines

### [Uniswap V3 Swapper Engine](uniswap-v3-swapper-engine.md)
