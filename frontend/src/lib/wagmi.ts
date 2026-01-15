import { http, createConfig } from "wagmi"
import { mainnet, sepolia, localhost } from "wagmi/chains"
import { injected, walletConnect } from "wagmi/connectors"
import { createPublicClient, type PublicClient } from "viem"
import ethereumLogo from "@/assets/ethereum.jpg"
import sepoliaLogo from "@/assets/sepolia.jpeg"

// Custom local chain configuration
const localChain = {
  ...localhost,
  name: "Local",
  id: 31337,
} as const

// Supported chains
export const supportedChains = [mainnet, sepolia, localChain] as const

// Chain icons - Logo images for each supported chain
export const chainIcons: Record<number, string> = {
  // Ethereum Mainnet
  [mainnet.id]: ethereumLogo,
  // Sepolia Testnet
  [sepolia.id]: sepoliaLogo,
  // Localhost/Anvil - Gear/cog icon (keep SVG since no image available)
  [localChain.id]: `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><circle cx="16" cy="16" r="16" fill="#404040"/><path fill="#10B981" d="M16 8a1 1 0 0 1 1 1v1.07a5.001 5.001 0 0 1 3.35 1.58l.76-.76a1 1 0 1 1 1.42 1.42l-.76.76A5.001 5.001 0 0 1 23.35 16H24.5a1 1 0 1 1 0 2h-1.15a5.001 5.001 0 0 1-1.58 3.35l.76.76a1 1 0 1 1-1.42 1.42l-.76-.76A5.001 5.001 0 0 1 17 24.35V25.5a1 1 0 1 1-2 0v-1.15a5.001 5.001 0 0 1-3.35-1.58l-.76.76a1 1 0 1 1-1.42-1.42l.76-.76A5.001 5.001 0 0 1 8.65 18H7.5a1 1 0 1 1 0-2h1.15a5.001 5.001 0 0 1 1.58-3.35l-.76-.76a1 1 0 1 1 1.42-1.42l.76.76A5.001 5.001 0 0 1 15 9.07V8a1 1 0 0 1 1-1zm0 5a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"/></svg>`)}`,
}

// Chain badge colors for UI indicators
export const chainColors: Record<number, { bg: string; text: string; border: string }> = {
  [mainnet.id]: { bg: "bg-blue-500/10", text: "text-blue-500", border: "border-blue-500/30" },
  [sepolia.id]: { bg: "bg-purple-500/10", text: "text-purple-500", border: "border-purple-500/30" },
  [localChain.id]: { bg: "bg-emerald-500/10", text: "text-emerald-500", border: "border-emerald-500/30" },
}

export interface ChainInfo {
  id: number
  name: string
  icon: string
  colors: { bg: string; text: string; border: string }
  isTestnet: boolean
}

// Get all supported chains with their metadata
export function getSupportedChainsInfo(): ChainInfo[] {
  return supportedChains.map((chain) => ({
    id: chain.id,
    name: chain.name,
    icon: chainIcons[chain.id] ?? "",
    colors: chainColors[chain.id] ?? { bg: "bg-gray-500/10", text: "text-gray-500", border: "border-gray-500/30" },
    isTestnet: chain.id !== mainnet.id,
  }))
}

// Get chain info by ID
export function getChainInfo(chainId: number): ChainInfo | undefined {
  const chain = supportedChains.find((c) => c.id === chainId)
  if (!chain) return undefined
  
  return {
    id: chain.id,
    name: chain.name,
    icon: chainIcons[chain.id] ?? "",
    colors: chainColors[chain.id] ?? { bg: "bg-gray-500/10", text: "text-gray-500", border: "border-gray-500/30" },
    isTestnet: chain.id !== mainnet.id,
  }
}

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

// Get a public client for a specific chain ID
export function getPublicClientForChain(chainId: number): PublicClient | null {
  const chain = getChainById(chainId)
  if (!chain) return null

  let transport
  if (chainId === mainnet.id) {
    transport = http(mainnetRpc)
  } else if (chainId === sepolia.id) {
    transport = http(sepoliaRpc)
  } else if (chainId === localChain.id) {
    transport = http(localRpc)
  } else {
    return null
  }

  return createPublicClient({
    chain,
    transport,
  })
}

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig
  }
}
