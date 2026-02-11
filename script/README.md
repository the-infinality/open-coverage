# Scripts

## Setup test chain

```shell
anvil --fork-url sepolia --fork-chain-id 11155111 --fork-block-number 10031916
```

## DeployEigenProvider

Deploys the Eigen Provider contract.

```shell
forge script script/DeployEigenProvider.sol:DeployEigenProvider --account <account> --sender <sender> --rpc-url anvil --chain-id <chain-id> --broadcast
```