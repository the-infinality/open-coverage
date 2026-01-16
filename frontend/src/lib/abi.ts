import type { Abi } from "viem"
import type { ContractType, ProviderType } from "@/types/contracts"
import { iCoverageAgentAbi, iCoverageProviderAbi, iEigenServiceManagerAbi } from "@/generated/abis"

export interface NamedAbi {
  name: string
  abi: Abi
}

/**
 * Get the named ABIs for a given contract type
 * @param contractType - The type of contract (CoverageAgent or CoverageProvider)
 * @param providerType - Optional provider type for CoverageProvider contracts
 * @returns Array of named ABIs for the contract type
 */
export function getAbisForContractType(contractType: ContractType, providerType?: ProviderType): NamedAbi[] {
  switch (contractType) {
    case "CoverageAgent":
      return [{ name: "ICoverageAgent", abi: iCoverageAgentAbi as Abi }]
    case "CoverageProvider":
      if (providerType === "EigenLayer") {
        return [
          { name: "ICoverageProvider", abi: iCoverageProviderAbi as Abi },
          { name: "IEigenServiceManager", abi: iEigenServiceManagerAbi as Abi },
        ]
      }
      return [{ name: "ICoverageProvider", abi: iCoverageProviderAbi as Abi }]
    default:
      throw new Error(`Unknown contract type: ${contractType}`)
  }
}

/**
 * Get a merged ABI for a given contract type (flattens multiple ABIs into one)
 * @param contractType - The type of contract (CoverageAgent or CoverageProvider)
 * @param providerType - Optional provider type for CoverageProvider contracts
 * @returns Merged ABI array for the contract type
 */
export function getMergedAbiForContractType(contractType: ContractType, providerType?: ProviderType): Abi {
  const namedAbis = getAbisForContractType(contractType, providerType)
  return namedAbis.flatMap(n => n.abi) as Abi
}
