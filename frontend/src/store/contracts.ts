import type { SavedContract, ContractType } from "@/types/contracts"
import type { Address } from "viem"

const STORAGE_KEY = "open-coverage-contracts"

export function getStoredContracts(): SavedContract[] {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (!stored) return []
    return JSON.parse(stored)
  } catch {
    return []
  }
}

export function saveContract(contract: SavedContract): void {
  const contracts = getStoredContracts()
  const existing = contracts.findIndex((c) => c.id === contract.id)
  if (existing >= 0) {
    contracts[existing] = contract
  } else {
    contracts.push(contract)
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(contracts))
}

export function removeContract(id: string): void {
  const contracts = getStoredContracts().filter((c) => c.id !== id)
  localStorage.setItem(STORAGE_KEY, JSON.stringify(contracts))
}

export function getContractById(id: string): SavedContract | undefined {
  return getStoredContracts().find((c) => c.id === id)
}

export function getContractByAddress(
  address: Address,
  chainId: number
): SavedContract | undefined {
  return getStoredContracts().find(
    (c) => c.address.toLowerCase() === address.toLowerCase() && c.chainId === chainId
  )
}

export function getContractsByType(type: ContractType): SavedContract[] {
  return getStoredContracts().filter((c) => c.type === type)
}

export function generateContractId(): string {
  return `contract-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
}
