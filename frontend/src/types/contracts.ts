import type { Abi, Address } from "viem"

export type ContractType = 
  | "CoverageAgent"
  | "CoverageProvider"

export type ProviderType = "EigenLayer" | "Catalysis" | "Symbiotic"

export interface SavedContract {
  id: string
  name: string
  address: Address
  type: ContractType
  chainId: number
  abi?: Abi
  createdAt: number
  ownerAddress?: Address
  providerType?: ProviderType
}

export interface ContractMethod {
  name: string
  type: "function" | "event"
  stateMutability?: "pure" | "view" | "nonpayable" | "payable"
  inputs: Array<{
    name: string
    type: string
    indexed?: boolean
  }>
  outputs?: Array<{
    name: string
    type: string
  }>
}

export interface ContractLog {
  address: Address
  blockNumber: bigint
  transactionHash: `0x${string}`
  logIndex: number
  eventName: string
  args: Record<string, unknown>
  timestamp?: number
}

export interface SimulationResult {
  success: boolean
  result?: unknown
  error?: string
  gasUsed?: bigint
}
