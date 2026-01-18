import type { Abi } from "viem"
import type { ContractType } from "@/types/contracts"
import { iCoverageAgentAbi, iCoverageProviderAbi, iEigenServiceManagerAbi, iAssetPriceOracleAndSwapperAbi, iEigenOperatorProxyAbi, iDiamondOwnerAbi } from "@/generated/abis"
import type { InterfaceName } from "@/lib/interface-ids"

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
export function getAbisForContractType(contractType: ContractType): NamedAbi[] {
  switch (contractType) {
    case "CoverageAgent":
      return [{ name: "ICoverageAgent", abi: iCoverageAgentAbi as Abi }]
    case "EigenOperatorProxy":
      return [{ name: "IEigenOperatorProxy", abi: iEigenOperatorProxyAbi as Abi }]
    default:
      throw new Error(`Unknown contract type: ${contractType}`)
  }
}

/**
 * Get the named ABIs for a CoverageProvider based on detected interface support
 * @param supportedInterfaces - Record of interface names to their support status
 * @returns Array of named ABIs based on supported interfaces
 */
export function getAbisForCoverageProviderWithInterfaces(
  supportedInterfaces: Record<InterfaceName, boolean>
): NamedAbi[] {
  const abis: NamedAbi[] = []

  if (supportedInterfaces.ICoverageProvider) {
    abis.push({ name: "ICoverageProvider", abi: iCoverageProviderAbi as Abi })
  }

  if (supportedInterfaces.IEigenServiceManager) {
    abis.push({ name: "IEigenServiceManager", abi: iEigenServiceManagerAbi as Abi })
  }

  if (supportedInterfaces.IAssetPriceOracleAndSwapper) {
    abis.push({ name: "IAssetPriceOracleAndSwapper", abi: iAssetPriceOracleAndSwapperAbi as Abi })
  }

  if (supportedInterfaces.IDiamondOwner) {
    abis.push({ name: "IDiamondOwner", abi: iDiamondOwnerAbi as Abi })
  }

  return abis
}

/**
 * Get a merged ABI for a given contract type (flattens multiple ABIs into one)
 * @param contractType - The type of contract (CoverageAgent or CoverageProvider)
 * @param providerType - Optional provider type for CoverageProvider contracts
 * @returns Merged ABI array for the contract type
 */
export function getMergedAbiForContractType(contractType: ContractType): Abi {
  const namedAbis = getAbisForContractType(contractType)
  return namedAbis.flatMap(n => n.abi) as Abi
}
