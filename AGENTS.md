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

### Pre-commit checks

The following checks **must** pass before every commit:

1. **`forge fmt`** — auto-formats all Solidity files (run from repo root)
2. **`forge test`** — runs the full Solidity test suite (requires `MAINNET_ARCHIVE_RPC`)
3. **`cd frontend && yarn lint`** — ESLint must exit with zero errors

Run all three in order before committing. `forge fmt` modifies files in-place (no `--check` flag), so stage any reformatted files before committing.

### Key caveats

- **Git submodules must be initialized** before `forge build` will work. Run `git submodule update --init --recursive` if `lib/` directories are empty.
- **Tests require a mainnet archive RPC** set as `MAINNET_ARCHIVE_RPC` in the root `.env` file. A free public endpoint like `https://eth.llamarpc.com` works but may be rate-limited. For reliable testing, use a dedicated Alchemy/Infura key.
- The frontend `.env` is copied from `.env.example` and does not require secret values for local dev.
- Contract dependencies are managed as git submodules (not npm). See `foundry.toml` for remapping paths.
