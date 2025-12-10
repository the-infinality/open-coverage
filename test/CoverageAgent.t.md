# CoverageAgent Test Suite

## Overview

This test suite provides comprehensive coverage for the `CoverageAgent` contract, including integration with `AssetPriceOracleAndSwapper` functionality.

## Test Components

### Mock Contracts

#### MockPriceOracle
- Implements `IPriceOracle` interface
- Returns 1:1 price quotes for testing
- Used to test price oracle integration

#### MockCoverageProvider
- Full implementation of `ICoverageProvider` interface
- Tracks positions and claims
- Simulates coverage provider behavior
- Manages coverage issuance, liquidation, completion, and slashing

#### CoverageAgentWithSwapper
- Extends `CoverageAgent` with `AssetPriceOracleAndSwapper`
- Provides swap and price oracle functionality
- Demonstrates how CoverageAgent can be extended

## Test Categories

### 1. Constructor Tests
- ✅ `test_constructor` - Verifies handler and coverage asset initialization
- ✅ `test_constructor_asset` - Verifies the `asset()` getter returns correct asset
- ✅ `test_RevertWhen_constructor_zeroHandler` - Ensures zero address handler is rejected

### 2. Coverage Provider Registration Tests
- ✅ `test_registerCoverageProvider` - Tests basic provider registration
- ✅ `test_RevertWhen_registerCoverageProvider_notHandler` - Ensures only handler can register
- ✅ `test_registerMultipleCoverageProviders` - Tests registering multiple providers

### 3. Position Registration Tests
- ✅ `test_onRegisterPosition` - Tests position registration callback
- ✅ `test_RevertWhen_onRegisterPosition_providerNotActive` - Ensures inactive providers cannot register positions
- ✅ `test_onRegisterPosition_throughProvider` - Tests full flow through provider

### 4. Coverage Provider Data Tests
- ✅ `test_coverageProviderData_inactive` - Tests querying inactive provider data
- ✅ `test_coverageProviderData_active` - Tests querying active provider data

### 5. AssetPriceOracleAndSwapper Tests
- ✅ `test_assetPriceOracleRegistered` - Verifies price oracle registration
- ✅ `test_quote` - Tests price quote functionality
- ✅ `test_quote_reverseDirection` - Tests bidirectional price quotes
- ✅ `test_swap_uniswapV4` - Tests Uniswap V4 swap execution
- ✅ `test_swap_uniswapV3` - Tests Uniswap V3 swap execution
- ✅ `test_RevertWhen_swap_assetPairNotRegistered` - Tests swap with unregistered pair
- ✅ `test_RevertWhen_quote_assetPairNotRegistered` - Tests quote with unregistered pair

### 6. Integration Tests
- ✅ `test_fullWorkflow_registerAndCreatePosition` - Full end-to-end workflow:
  1. Register coverage provider
  2. Create coverage position
  3. Issue coverage claim
  4. Verify all state changes
  
- ✅ `test_multipleProviders_andPositions` - Tests multiple providers with different positions

## Test Execution

### Run all CoverageAgent tests:
```bash
forge test --match-contract CoverageAgentTest -vv
```

### Run specific test:
```bash
forge test --match-test test_registerCoverageProvider -vvv
```

### Run with gas reporting:
```bash
forge test --match-contract CoverageAgentTest --gas-report
```

## Coverage

The test suite covers:
- ✅ All public functions
- ✅ Access control (handler-only functions)
- ✅ Event emissions
- ✅ State changes
- ✅ Error conditions
- ✅ Integration with external contracts (Uniswap, price oracles)
- ✅ Multiple provider scenarios
- ✅ Full workflow scenarios

## Key Features Tested

1. **Access Control**: Verified that only the handler can perform privileged operations
2. **Provider Management**: Registration, activation tracking, and listing
3. **Position Management**: Registration callback and validation
4. **Asset Management**: Correct asset tracking and retrieval
5. **Price Oracle Integration**: Quote retrieval and validation
6. **Swap Functionality**: Both Uniswap V3 and V4 swap engines
7. **Error Handling**: All revert conditions properly tested

## Dependencies

The tests require:
- Ethereum mainnet fork (configured in `foundry.toml`)
- Mainnet RPC URL in environment (`MAINNET_ARCHIVE_RPC`)
- Config files in `/config` directory:
  - `chains.json` - Chain and asset addresses
  - `uniswap.json` - Uniswap router and pool configurations

## Notes

- Tests use mainnet fork at block 23974509 for consistent state
- USDC and USDT addresses are loaded from `chains.json`
- Uniswap router addresses loaded from `uniswap.json`
- Mock contracts simulate real provider behavior for isolated testing

