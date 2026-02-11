# Facet Deployment

This guide explains how to deploy diamond facets and record them in `config/deployments.json`. All facet deployment scripts live in **`script/facets/`**. There are **three scripts**:

| Script | Facets |
|--------|--------|
| **DeployDiamondFacets** | Core diamond facets (DiamondCut, DiamondLoupe, Ownership) |
| **DeployEigenProviderFacets** | Eigen provider facets (EigenServiceManager, EigenCoverageProvider) |
| **DeployAssetPriceOracleAndSwapperFacet** | AssetPriceOracleAndSwapper facet (price oracle + swapper) |

Deploy the core facets first if you are building a new diamond; add Eigen provider facets when deploying or upgrading an Eigen coverage diamond. Deploy **AssetPriceOracleAndSwapperFacet** when you need a new version for upgrading existing diamonds (e.g. via `UpgradeAssetPriceOracleAndSwapperFacet`).

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- An account with ETH on the target network (for gas)
- For live networks: `--account` set up in `foundry.toml` or use `--private-key`
- Run commands in an **interactive terminal** when existing deployments might be overwritten (so you can answer the prompt)

---

## Override behavior (all scripts)

If `config/deployments.json` already has entries for **any of the facets deployed by that script** on the target chain, the script will **prompt** before continuing:

```
Facet deployments already exist for chain <chain-id>
Type 'y' to override existing deployment properties and continue:
```

- Type **`y`** and press Enter to overwrite existing addresses and continue.
- Any other input (or skipping input) cancels with: `Deployment cancelled (expected 'y' to override)`.

---

## 1. Core diamond facets (DeployDiamondFacets)

Deploys the three facets required for any diamond: cut, loupe, and ownership.

### What gets deployed

- **DiamondCutFacet** – diamond upgrade / cut operations
- **DiamondLoupeFacet** – facet inspection (facets, selectors)
- **OwnershipFacet** – owner and transfer ownership

### Dry run (no broadcast)

```bash
forge script script/facets/DeployDiamondFacets.sol:DeployDiamondFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id>
```

### Deploy and broadcast

```bash
forge script script/facets/DeployDiamondFacets.sol:DeployDiamondFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

### Local Anvil

```bash
forge script script/facets/DeployDiamondFacets.sol:DeployDiamondFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

---

## 2. Eigen provider facets (DeployEigenProviderFacets)

Deploys the two facets used by the Eigen coverage diamond (EigenCoverageDiamond).

### What gets deployed

- **EigenServiceManagerFacet** – Eigen operator registration, allocations, rewards, slashing, AVS metadata
- **EigenCoverageProviderFacet** – coverage provider interface (positions, claims, slash handling)

### Dry run (no broadcast)

```bash
forge script script/facets/DeployEigenProviderFacets.sol:DeployEigenProviderFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id>
```

### Deploy and broadcast

```bash
forge script script/facets/DeployEigenProviderFacets.sol:DeployEigenProviderFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

### Local Anvil

```bash
forge script script/facets/DeployEigenProviderFacets.sol:DeployEigenProviderFacets \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

---

## 3. AssetPriceOracleAndSwapper facet (DeployAssetPriceOracleAndSwapperFacet)

Deploys the **AssetPriceOracleAndSwapperFacet** standalone. Use this when you need a new facet implementation (e.g. for upgrading an existing diamond via `UpgradeAssetPriceOracleAndSwapperFacet`).

### What gets deployed

- **AssetPriceOracleAndSwapperFacet** – asset price oracle and swapper (register, swap, quotes, slippage)

### Dry run (no broadcast)

```bash
forge script script/facets/DeployAssetPriceOracleAndSwapperFacet.sol:DeployAssetPriceOracleAndSwapperFacet \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id>
```

### Deploy and broadcast

```bash
forge script script/facets/DeployAssetPriceOracleAndSwapperFacet.sol:DeployAssetPriceOracleAndSwapperFacet \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

### Local Anvil

```bash
forge script script/facets/DeployAssetPriceOracleAndSwapperFacet.sol:DeployAssetPriceOracleAndSwapperFacet \
  --rpc-url <rpc-url> \
  --account <account> \
  --sender <sender-address> \
  --chain-id <chain-id> \
  --broadcast
```

After deployment, use **UpgradeAssetPriceOracleAndSwapperFacet** to upgrade your diamond to this new facet address.

---

## Flag reference

| Flag | Description |
|------|-------------|
| `--rpc-url <rpc-url>` | RPC endpoint (e.g. named endpoint from `foundry.toml` or a URL). |
| `--account <account>` | Account name from `foundry.toml` (or use `--private-key`). |
| `--sender <sender-address>` | Address that sends the transactions (deployer). |
| `--chain-id <chain-id>` | Chain ID for the target network. |
| `--broadcast` | Send transactions and update state; omit for dry run. |

---

## After deployment

- Broadcast artifacts: `broadcast/script/facets/DeployDiamondFacets.sol/<chain-id>/`, `broadcast/script/facets/DeployEigenProviderFacets.sol/<chain-id>/`, and `broadcast/script/facets/DeployAssetPriceOracleAndSwapperFacet.sol/<chain-id>/`.
- Addresses are written to `config/deployments.json` under the chain ID. Each script only writes its own facet keys; other keys (from other scripts or chains) are preserved.

Example `config/deployments.json` after deploying all facet scripts:

```json
"<chain-id>": {
  "DiamondCutFacet": "0x...",
  "DiamondLoupeFacet": "0x...",
  "OwnershipFacet": "0x...",
  "EigenServiceManagerFacet": "0x...",
  "EigenCoverageProviderFacet": "0x...",
  "AssetPriceOracleAndSwapperFacet": "0x..."
}
```

Use these addresses when deploying or upgrading a diamond (e.g. `DeployEigenProvider`) or when upgrading the AssetPriceOracleAndSwapper facet (`UpgradeAssetPriceOracleAndSwapperFacet`).
