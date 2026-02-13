import { type Abi, toFunctionSelector } from "viem"
import {
    iEigenServiceManagerAbi,
    iAssetPriceOracleAndSwapperAbi,
    iCoverageProviderAbi,
    ierc173Abi,
    iExampleCoverageAgentAbi,
    iCoverageAgentAbi,
    iEigenOperatorProxyAbi,
} from "@/generated/abis"

/**
 * Computes the ERC-165 interface ID from an ABI by XORing all function selectors
 * @param abi - The ABI to compute the interface ID for
 * @returns The interface ID as a hex string
 */
function computeInterfaceId(abi: Abi): `0x${string}` {
    const functionSelectors = abi
        .filter((item) => item.type === "function")
        .map((item) => toFunctionSelector(item))

    // XOR all selectors together, using >>> 0 to ensure unsigned 32-bit result
    const interfaceId = functionSelectors.reduce((acc, selector) => {
        const selectorNum = parseInt(selector.slice(2), 16)
        return (acc ^ selectorNum) >>> 0
    }, 0)

    // Convert back to hex string with 0x prefix, padded to 8 chars
    return `0x${interfaceId.toString(16).padStart(8, "0")}`
}

// Interface IDs computed dynamically from ABIs using ERC-165 standard
export const INTERFACE_IDS = {
    IEigenServiceManager: computeInterfaceId(iEigenServiceManagerAbi),
    IAssetPriceOracleAndSwapper: computeInterfaceId(iAssetPriceOracleAndSwapperAbi),
    ICoverageProvider: computeInterfaceId(iCoverageProviderAbi),
    IExampleCoverageAgent: computeInterfaceId(iExampleCoverageAgentAbi),
    ICoverageAgent: computeInterfaceId(iCoverageAgentAbi),
    IEigenOperatorProxy: computeInterfaceId(iEigenOperatorProxyAbi),
    IERC173: computeInterfaceId(ierc173Abi),
} as const

console.log(INTERFACE_IDS)

export type InterfaceName = keyof typeof INTERFACE_IDS
