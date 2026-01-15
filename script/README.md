# Scripts

## Setup test chain

```shell
anvil --fork-url sepolia --fork-chain-id 11155111 --fork-block-number 10031916
```

## DeployEigenProviderTestnet

Deploys the EigenProviderTestnet contract.

```shell
forge script script/DeployEigenProviderTestnet.sol:DeployEigenProviderTestnet --account <account> --sender <sender> --rpc-url anvil --chain-id <chain-id> --broadcast
```