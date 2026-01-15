import type { Abi } from "viem"
import type { ContractType } from "@/types/contracts"
import { iCoverageAgentAbi, iCoverageProviderAbi } from "@/generated/abis"

/**
 * Get the ABI for a given contract type
 * @param contractType - The type of contract (CoverageAgent or CoverageProvider)
 * @returns The ABI array for the contract type
 */
export function getAbiForContractType(contractType: ContractType): Abi {
  switch (contractType) {
    case "CoverageAgent":
      return iCoverageAgentAbi as Abi
    case "CoverageProvider":
      return iCoverageProviderAbi as Abi
    default:
      throw new Error(`Unknown contract type: ${contractType}`)
  }
}

