import type { Abi } from "viem"
import type { ContractType } from "@/types/contracts"
import {
    iCoverageAgentAbi,
    iCoverageProviderAbi,
    iEigenServiceManagerAbi,
    iAssetPriceOracleAndSwapperAbi,
    iEigenOperatorProxyAbi,
    iDiamondOwnerAbi,
    iExampleCoverageAgentAbi,
} from "@/generated/abis"
import type { InterfaceName } from "@/lib/interface-ids"

export interface NamedAbi {
    name: string
    abi: Abi
}

// Mapping from interface names to their ABIs
const INTERFACE_ABIS: Record<InterfaceName, Abi> = {
    IEigenServiceManager: iEigenServiceManagerAbi as Abi,
    IAssetPriceOracleAndSwapper: iAssetPriceOracleAndSwapperAbi as Abi,
    ICoverageProvider: iCoverageProviderAbi as Abi,
    IDiamondOwner: iDiamondOwnerAbi as Abi,
    IExampleCoverageAgent: iExampleCoverageAgentAbi as Abi,
    ICoverageAgent: iCoverageAgentAbi as Abi,
    IEigenOperatorProxy: iEigenOperatorProxyAbi as Abi,
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
        case "CoverageProvider":
            return [{ name: "ICoverageProvider", abi: iCoverageProviderAbi as Abi }]
        default:
            throw new Error(`Unknown contract type: ${contractType}`)
    }
}

/**
 * Get the named ABIs for supported interfaces
 * @param supportedInterfaces - Array of supported interface names
 * @returns Array of named ABIs based on supported interfaces
 */
export function getAbisForSupportedInterfaces(supportedInterfaces: InterfaceName[]): NamedAbi[] {
    console.log("supportedInterfaces", supportedInterfaces)
    return supportedInterfaces.map((interfaceName) => ({
        name: interfaceName,
        abi: INTERFACE_ABIS[interfaceName],
    }))
}

/**
 * Get a merged ABI for a given contract type (flattens multiple ABIs into one)
 * @param contractType - The type of contract (CoverageAgent or CoverageProvider)
 * @param providerType - Optional provider type for CoverageProvider contracts
 * @returns Merged ABI array for the contract type
 */
export function getMergedAbiForContractType(contractType: ContractType): Abi {
    const namedAbis = getAbisForContractType(contractType)
    return namedAbis.flatMap((n) => n.abi) as Abi
}
