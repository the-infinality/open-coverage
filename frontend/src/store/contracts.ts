import type { CoverageContract, ContractType } from "@/types/contracts"
import type { Address } from "viem"

const STORAGE_KEY = "open-coverage-contracts"

export function getStoredContracts(): CoverageContract[] {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (!stored) return []
    return JSON.parse(stored)
  } catch {
    return []
  }
}

export function saveContract(contract: CoverageContract): void {
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

export function getContractById(id: string): CoverageContract | undefined {
  return getStoredContracts().find((c) => c.id === id)
}

export function getContractByAddress(
  address: Address,
  chainId: number
): CoverageContract | undefined {
  return getStoredContracts().find(
    (c) => c.address.toLowerCase() === address.toLowerCase() && c.chainId === chainId
  )
}

export function getContractsByType(type: ContractType): CoverageContract[] {
  return getStoredContracts().filter((c) => c.type === type)
}

export function generateContractId(chainId: number, address: Address): string {
  return `${chainId}-${address.toLowerCase()}`
}
