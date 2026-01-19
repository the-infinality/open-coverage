# Open Coverage Frontend

An interactive frontend for testing the Open Coverage System. This application allows you to manage and interact with Coverage Agent, Coverage Provider, and Eigen Service Manager contracts.

## Features

- **Contract Management**: Add, view, and remove contracts stored locally in browser storage
- **Contract Interaction**: Read and write to contracts using their ABIs (similar to Etherscan)
- **Contract Logs**: View event logs emitted by contracts
- **Wallet Connection**: Connect your wallet using injected providers or WalletConnect
- **Multi-Chain Support**: Works with Local, Mainnet, and Sepolia networks (configurable via env vars)
- **Dark/Light Theme**: System-based theming with manual override

## Tech Stack

- **React** - UI Framework
- **Vite** - Build tool
- **TypeScript** - Type safety
- **react-router** - Client-side routing
- **shadcn/ui** - Component library (built on Radix UI)
- **Tailwind CSS** - Styling
- **viem** - Ethereum interactions
- **wagmi** - React hooks for Ethereum
- **zod** - Schema validation
- **react-hook-form** - Form handling

## Getting Started

### Prerequisites

- Node.js 18+
- Yarn

### Installation

```bash
cd frontend
yarn install
```

### Development

```bash
yarn dev
```

The app will be available at `http://localhost:5173`

### Production Build

```bash
yarn build
```

### Preview Production Build

```bash
yarn preview
```

## Project Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── layout/       # Layout components (Sidebar, Header)
│   │   └── ui/           # shadcn/ui components
│   ├── generated/        # Generated ABIs and contract types
│   ├── hooks/            # Custom React hooks
│   ├── lib/              # Utility functions and configs
│   ├── pages/            # Page components
│   ├── store/            # Local storage management
│   └── types/            # TypeScript types
├── wagmi.config.ts       # Wagmi CLI configuration
└── vite.config.ts        # Vite configuration
```

## Contract Types

The frontend supports the following contract types:

1. **Coverage Agent** - The main coverage agent interface
2. **Coverage Provider** - Coverage provider implementation
3. **Eigen Service Manager** - EigenLayer service manager interface

## Regenerating ABIs

If the contract ABIs change, you can regenerate them using:

```bash
# From the project root
cd ..
forge build

# Then update the ABIs in src/generated/abis.ts
```

Or use the wagmi CLI:

```bash
npx wagmi generate
```

## Environment Variables

| Variable                        | Description                                    | Default                    |
| ------------------------------- | ---------------------------------------------- | -------------------------- |
| `VITE_LOCAL_RPC`                | RPC URL for local network                      | `http://127.0.0.1:8545`    |
| `VITE_MAINNET_ARCHIVE_RPC`      | RPC URL for Ethereum Mainnet                   | `https://eth.llamarpc.com` |
| `VITE_SEPOLIA_ARCHIVE_RPC`      | RPC URL for Sepolia testnet                    | `https://rpc.sepolia.org`  |
| `VITE_WALLETCONNECT_PROJECT_ID` | WalletConnect Project ID for wallet connection | `demo`                     |

Copy `.env.example` to `.env` and configure your RPC URLs:

```bash
cp .env.example .env
```

## Usage

1. **Add a Contract**: Navigate to the home page and fill in the contract details
2. **View Contracts**: Go to "Manage Contracts" to see all saved contracts
3. **Interact**: Select a contract and use the Read/Write tabs to interact with it
4. **View Logs**: Select a contract and fetch event logs within a block range

## Local Storage

All contract data is stored in the browser's local storage under the key `open-coverage-contracts`. This means:

- Data persists across browser sessions
- Each user has their own local contract list
- Clearing browser data will remove saved contracts

## License

MIT
