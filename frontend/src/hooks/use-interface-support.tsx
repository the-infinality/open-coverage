import { useMemo } from "react"
import { useReadContracts } from "wagmi"
import { INTERFACE_IDS, type InterfaceName } from "@/lib/interface-ids"
import { supportedChains } from "@/lib/wagmi"
import type { ProviderType } from "@/types/contracts"

// ERC-165 supportsInterface ABI
const erc165Abi = [
    {
        type: "function",
        name: "supportsInterface",
        inputs: [{ name: "interfaceId", type: "bytes4" }],
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "view",
    },
] as const

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface InterfaceSupportResult {
    isLoading: boolean
    supports: Record<InterfaceName, boolean>
}

/**
 * Hook to check if a contract supports specific interfaces via ERC-165
 * @param contractAddress The contract address to check
 * @param chainId The chain ID where the contract is deployed
 * @param interfaces The interfaces to check support for
 * @returns Object with loading state and support results
 */
export function useCheckCoverageProviderSupport(
    contractAddress: `0x${string}`,
    chainId: number,
    interfaces: InterfaceName[] = [
        "IEigenServiceManager",
        "IAssetPriceOracleAndSwapper",
        "IDiamondOwner",
        "ICoverageProvider",
    ]
): InterfaceSupportResult {
    const isChainSupported = supportedChains.some((chain) => chain.id === chainId)
    const supportedChainId = isChainSupported ? (chainId as SupportedChainId) : undefined

    // Build contract read configs for each interface
    const contracts = useMemo(() => {
        return interfaces.map((interfaceName) => ({
            address: contractAddress,
            abi: erc165Abi,
            functionName: "supportsInterface" as const,
            args: [INTERFACE_IDS[interfaceName]] as const,
            chainId: supportedChainId,
        }))
    }, [interfaces, contractAddress, supportedChainId])

    const { data, isLoading } = useReadContracts({
        contracts,
        query: {
            enabled: isChainSupported,
        },
    })

    // Build the supports record from the results
    const supports = useMemo(() => {
        const result: Record<InterfaceName, boolean> = {
            IEigenServiceManager: false,
            IAssetPriceOracleAndSwapper: false,
            ICoverageProvider: false,
            IDiamondOwner: false,
        }

        if (data) {
            interfaces.forEach((interfaceName, index) => {
                const queryResult = data[index]
                // Check if the result is successful and truthy
                result[interfaceName] =
                    queryResult?.status === "success" && Boolean(queryResult.result)
            })
        }

        return result
    }, [data, interfaces])

    return { isLoading, supports }
}

const coverageProviderMapping: Record<"IEigenServiceManager", ProviderType> = {
    IEigenServiceManager: "EigenLayer",
}

const coverageProviderInterfaces: InterfaceName[] = Object.keys(
    coverageProviderMapping
) as InterfaceName[]

export function useCheckCoverageProvider(
    contractAddress: `0x${string}` | undefined,
    chainId: number
): { isLoading: boolean; coverageProvider: ProviderType | null } {
    const isChainSupported = supportedChains.some((chain) => chain.id === chainId)
    const supportedChainId = isChainSupported ? (chainId as SupportedChainId) : undefined

    // Build contract read configs for each interface
    const contracts = coverageProviderInterfaces.map((interfaceName) => ({
        address: contractAddress,
        abi: erc165Abi,
        functionName: "supportsInterface" as const,
        args: [INTERFACE_IDS[interfaceName]] as const,
        chainId: supportedChainId,
    }))

    const { data, isLoading } = useReadContracts({
        contracts,
        query: {
            enabled: isChainSupported,
        },
    })

    // Build the supports record from the results
    const coverageProvider = useMemo(() => {
        if (data) {
            for (let i = 0; i < coverageProviderInterfaces.length; i++) {
                const interfaceName = coverageProviderInterfaces[i]
                const queryResult = data[i]
                // Check if the result is successful and truthy
                if (queryResult?.status === "success" && Boolean(queryResult.result)) {
                    return coverageProviderMapping[
                        interfaceName as keyof typeof coverageProviderMapping
                    ]
                }
            }
        }
        return null
    }, [data])

    return { isLoading, coverageProvider }
}
