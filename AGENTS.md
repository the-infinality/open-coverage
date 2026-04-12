# AGENTS.md

## Cursor Cloud specific instructions

### Overview

Open Coverage is a DeFi risk coverage protocol with two main components:

1. **Solidity Smart Contracts** (Foundry-based) — the core protocol in `src/`, tests in `test/`
2. **React Frontend DApp** (`frontend/`) — Vite + TypeScript + wagmi for contract interaction

### Running the smart contracts

- **Build:** `forge build`
- **Lint:** `forge fmt --check`
- **Test:** `forge test -vvv` (requires `MAINNET_ARCHIVE_RPC` env var — tests fork mainnet at a specific block)
- **Local node:** `anvil` (starts a local Ethereum node at `127.0.0.1:8545`)

Foundry must be on PATH: `export PATH="$HOME/.foundry/bin:$PATH"` (already in `~/.bashrc`).

### Running the frontend

- **Dev server:** `cd frontend && yarn dev` (runs on `http://localhost:5173`)
- **Build:** `cd frontend && yarn build` (runs `tsc -b && vite build`)
- **Lint:** `cd frontend && yarn lint` (ESLint)
- **Format check:** `cd frontend && yarn format:check` (Prettier)

### Testing with the frontend

When manually testing the frontend, use `config/deployments.json` to load deployed contracts. The Sepolia (chain ID `11155111`) deployments are the primary test targets:

| Contract | Sepolia Address |
|----------|----------------|
| `EigenCoverageDiamond` | `0x997102126a3B10AA7Bfd991ef4DE8E6E196AFDF2` |
| `ExampleCoverageAgent` | `0x533DC1904809a47991797aE64d955c1029c143B1` |
| `EigenServiceManagerFacet` | `0x6179f406C31ad3d0972fa0572A48E68c39a7a8EF` |
| `EigenCoverageProviderFacet` | `0x114E3772F69EaDF80792Bc90477A83a6dCC06344` |

Add these contracts in the frontend UI using their Sepolia addresses and the matching contract type (Coverage Agent, Coverage Provider, or Eigen Service Manager) to test contract interaction flows.

### Pre-commit checks

A Git pre-commit hook is installed at `.git/hooks/pre-commit` that enforces:

1. **`forge fmt --check`** — Solidity formatting must be correct
2. **`forge test`** — full Solidity test suite must pass

The hook runs automatically on `git commit`. If it fails, fix the issues and re-commit. Additionally, **`cd frontend && yarn lint`** must exit with zero errors before committing frontend changes.

### Key caveats

- **Git submodules must be initialized** before `forge build` will work. Run `git submodule update --init --recursive` if `lib/` directories are empty.
- **Tests require a mainnet archive RPC** set as `MAINNET_ARCHIVE_RPC` in the root `.env` file. A free public endpoint like `https://eth.llamarpc.com` works but may be rate-limited. For reliable testing, use a dedicated Alchemy/Infura key.
- The frontend `.env` is copied from `.env.example` and does not require secret values for local dev.
- Contract dependencies are managed as git submodules (not npm). See `foundry.toml` for remapping paths.
