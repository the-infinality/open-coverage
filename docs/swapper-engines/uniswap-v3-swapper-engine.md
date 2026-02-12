# Uniswap V3 Swapper Engine

## Links

- [Uniswap V3 Implementation Contract](src/swapper-engines/UniswapV3SwapperEngine.sol)

## Overview

An implementation of the Swapper Engine for the Uniswap V3 protocol.

## Implementation Details

### Swapping

Since the swapper engine is inspired by the Uniswap V3 `exactInput` and `exactOutput` functions the implementation is straightforward.

### Quoting

This required the usage of the Uniswap Quoter to get the quote for the swap by first getting a unit price quote for the asset to avoid precision issues when trying to calculate the quote for very large amounts. This is quite important to avoid liquidity issues during production allowing the swap path to be changed accordingly. **It is highly recommended monitoring is performed on the pools** to ensure operational integrity at all times.
