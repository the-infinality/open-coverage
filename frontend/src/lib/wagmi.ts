import { http, createConfig } from "wagmi"
import { mainnet, sepolia, localhost } from "wagmi/chains"
import { injected, walletConnect } from "wagmi/connectors"

// Custom local chain configuration
const localChain = {
  ...localhost,
  name: "Local",
  id: 31337,
} as const

// Supported chains
export const supportedChains = [localChain, mainnet, sepolia] as const

// WalletConnect Project ID - users can set their own via env
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "demo"

// RPC URLs from environment variables
const localRpc = import.meta.env.VITE_LOCAL_RPC || "http://127.0.0.1:8545"
const mainnetRpc = import.meta.env.VITE_MAINNET_ARCHIVE_RPC || "https://eth.llamarpc.com"
const sepoliaRpc = import.meta.env.VITE_SEPOLIA_ARCHIVE_RPC || "https://rpc.sepolia.org"

export const wagmiConfig = createConfig({
  chains: supportedChains,
  connectors: [
    injected(),
    ...(projectId !== "demo" ? [walletConnect({ projectId })] : []),
  ],
  transports: {
    [mainnet.id]: http(mainnetRpc),
    [sepolia.id]: http(sepoliaRpc),
    [localChain.id]: http(localRpc),
  },
})

export function getChainName(chainId: number): string {
  const chain = supportedChains.find((c) => c.id === chainId)
  return chain?.name ?? `Chain ${chainId}`
}

export function getChainById(chainId: number) {
  return supportedChains.find((c) => c.id === chainId)
}

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig
  }
}
