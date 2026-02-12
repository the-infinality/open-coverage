# Testing Guide

## Prerequisites

1. **Install Foundry**:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Install Dependencies**:
```bash
forge install
```

3. **Set up Environment Variables**:

Create a `.env` file in the project root:
```bash
# .env file
MAINNET_ARCHIVE_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
```

## Configuration Files

The tests rely on configuration files in the `/config` directory:

- **`config/chains.json`** - Contains chain configurations and asset addresses (USDC, USDT, etc.)
- **`config/uniswap.json`** - Contains Uniswap router addresses and pool configurations
- **`config/eigen.json`** - Contains EigenLayer contract addresses

These are already configured for Ethereum mainnet and are accessed via the file system permissions in `foundry.toml`:
```toml
fs_permissions = [{ access = "read", path = "./config"}]
```

## Running Tests

### Build the Project
```bash
forge build
```

### Run All Tests
```bash
forge test
```

### Run CoverageAgent Tests
```bash
forge test --match-contract CoverageAgentTest -vv
```

### Run Specific Test
```bash
forge test --match-test test_registerCoverageProvider -vvv
```

### Run with Gas Report
```bash
forge test --gas-report
```

### Run with Verbose Output
```bash
forge test -vvvv
```

## Test Suites

### CoverageAgent Tests (`test/CoverageAgent.t.sol`)
Comprehensive test suite covering:
- Constructor validation
- Coverage provider registration
- Position registration
- Access control
- AssetPriceOracleAndSwapper integration
- Uniswap V3 and V4 swaps
- Full workflow integration tests

See [`test/CoverageAgent.t.md`](test/CoverageAgent.t.md) for detailed documentation.

### EigenLayer Tests (`test/providers/Eigen.t.sol`)
Tests for EigenLayer-specific coverage provider implementation.

### AssetPriceOracleAndSwapper Tests (`test/mixins/AssetPriceOracleAndSwapper.t.sol`)
Tests for the price oracle and swap functionality mixin.

## Troubleshooting

### "Failed to create NULL object" Error
This typically means you need network access. The error occurs when Foundry tries to fetch contract signatures but doesn't have network permissions. This is expected and doesn't prevent tests from running locally with proper RPC configuration.

### "RPC URL not set" Error
Make sure your `.env` file exists and contains a valid `MAINNET_ARCHIVE_RPC` URL.

### Fork Block Number
Tests fork from mainnet block `23974509` (configured in `config/chains.json`). This ensures consistent test results with known contract states.

### Config File Access
If you get errors about reading config files, verify that `foundry.toml` has the proper `fs_permissions` setting:
```toml
fs_permissions = [{ access = "read", path = "./config"}]
```

## Writing New Tests

When writing new tests:

1. Extend `TestDeployer` for basic test setup with chain configs
2. Extend `UniswapHelper` if you need Uniswap functionality
3. Extend `EigenTestDeployer` for EigenLayer-specific tests
4. Use mock contracts when testing in isolation
5. Write integration tests for full workflow validation

Example:
```solidity
import {TestDeployer} from "test/utils/TestDeployer.sol";

contract MyContractTest is TestDeployer {
    function setUp() public override {
        super.setUp();
        // Your setup here
    }
    
    function test_myFunction() public {
        // Your test here
    }
}
```

## Coverage

To generate a coverage report:
```bash
forge coverage
```

To generate detailed coverage report:
```bash
forge coverage --report lcov
```

## CI/CD

For GitHub Actions or other CI systems, make sure to:
1. Set `MAINNET_ARCHIVE_RPC` as a secret
2. Install Foundry in your CI pipeline
3. Run `forge test` in your test step

Example GitHub Actions workflow:
```yaml
- name: Install Foundry
  uses: foundry-rs/foundry-toolchain@v1

- name: Run tests
  run: forge test
  env:
    MAINNET_ARCHIVE_RPC: ${{ secrets.MAINNET_ARCHIVE_RPC }}
```

