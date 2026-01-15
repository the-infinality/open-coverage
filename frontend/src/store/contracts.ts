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

export function exportContractsToJson(contractIds?: string[]): string {
  const allContracts = getStoredContracts()
  const contractsToExport = contractIds
    ? allContracts.filter((c) => contractIds.includes(c.id))
    : allContracts
  return JSON.stringify(contractsToExport, null, 2)
}

export function importContractsFromJson(
  json: string,
  overwrite: boolean = false
): {
  success: boolean
  imported: number
  updated: number
  errors: string[]
} {
  try {
    const parsed = JSON.parse(json)
    
    if (!Array.isArray(parsed)) {
      return {
        success: false,
        imported: 0,
        updated: 0,
        errors: ["Invalid format: JSON must be an array of contracts"],
      }
    }

    const errors: string[] = []
    const existingContracts = getStoredContracts()
    const existingIds = new Set(existingContracts.map((c) => c.id))
    const existingMap = new Map(existingContracts.map((c) => [c.id, c]))
    let imported = 0
    let updated = 0

    for (const contract of parsed) {
      // Validate required fields
      if (!contract.address || !contract.chainId || !contract.type) {
        errors.push(
          `Skipped contract: missing required fields (address, chainId, or type)`
        )
        continue
      }

      // Generate ID if not present
      const id = contract.id || generateContractId(contract.chainId, contract.address)

      // Handle existing contracts
      if (existingIds.has(id)) {
        if (overwrite) {
          // Update existing contract
          const existingIndex = existingContracts.findIndex((c) => c.id === id)
          if (existingIndex >= 0) {
            const existingContract = existingMap.get(id)!
            const updatedContract: CoverageContract = {
              id,
              name: contract.name || existingContract.name,
              address: contract.address.toLowerCase() as Address,
              type: contract.type,
              chainId: contract.chainId,
              abi: contract.abi ?? existingContract.abi,
              createdAt: existingContract.createdAt, // Preserve original creation date
              providerType: contract.providerType ?? existingContract.providerType,
            }
            existingContracts[existingIndex] = updatedContract
            updated++
          }
        } else {
          errors.push(`Skipped contract ${id}: already exists`)
        }
        continue
      }

      // Create new contract with defaults
      const newContract: CoverageContract = {
        id,
        name: contract.name || `Imported Contract ${imported + 1}`,
        address: contract.address.toLowerCase() as Address,
        type: contract.type,
        chainId: contract.chainId,
        abi: contract.abi,
        createdAt: contract.createdAt || Date.now(),
        providerType: contract.providerType,
      }

      existingContracts.push(newContract)
      existingIds.add(id)
      imported++
    }

    // Save all contracts
    localStorage.setItem(STORAGE_KEY, JSON.stringify(existingContracts))

    return {
      success: true,
      imported,
      updated,
      errors,
    }
  } catch (error) {
    return {
      success: false,
      imported: 0,
      updated: 0,
      errors: [`Failed to parse JSON: ${error instanceof Error ? error.message : "Unknown error"}`],
    }
  }
}
