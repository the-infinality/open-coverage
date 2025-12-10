## Open Coverage

A risk coverage standard focussed on simplifying the process of purchasing coverage.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Setup

1. Install Foundry if you haven't already:
```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```shell
forge install
```

3. Configure your environment:
```shell
cp .env.example .env
# Edit .env and add your Ethereum mainnet RPC URL
```

## Usage

### Build

```shell
forge build
```

### Test

Run all tests:
```shell
forge test
```

Run specific test contract:
```shell
forge test --match-contract CoverageAgentTest -vv
```

Run specific test:
```shell
forge test --match-test test_registerCoverageProvider -vvv
```

Run tests with gas reporting:
```shell
forge test --gas-report
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
