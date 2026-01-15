import { http, createConfig } from "wagmi"
import { mainnet, sepolia, holesky, localhost } from "wagmi/chains"
import { injected, walletConnect } from "wagmi/connectors"

// Supported chains
export const supportedChains = [mainnet, sepolia, holesky, localhost] as const

// WalletConnect Project ID - users can set their own via env
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "demo"

export const wagmiConfig = createConfig({
  chains: supportedChains,
  connectors: [
    injected(),
    ...(projectId !== "demo" ? [walletConnect({ projectId })] : []),
  ],
  transports: {
    [mainnet.id]: http(),
    [sepolia.id]: http(),
    [holesky.id]: http(),
    [localhost.id]: http("http://127.0.0.1:8545"),
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
