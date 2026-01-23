import { useMemo } from "react"
import { useReadContracts } from "wagmi"
import { INTERFACE_IDS, type InterfaceName } from "@/lib/interface-ids"
import { getAbisForSupportedInterfaces, type NamedAbi } from "@/lib/abi"
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

// Get all interface names from INTERFACE_IDS
const ALL_INTERFACE_NAMES = Object.keys(INTERFACE_IDS) as InterfaceName[]

interface InterfaceSupportResult {
    isLoading: boolean
    supportedInterfaces: InterfaceName[]
    abis: NamedAbi[]
}

/**
 * Hook to check if a contract supports specific interfaces via ERC-165
 * @param contractAddress The contract address to check
 * @param chainId The chain ID where the contract is deployed
 * @param interfaces The interfaces to check support for. If undefined, checks all interfaces from INTERFACE_IDS
 * @returns Object with loading state and array of supported interface names
 */
export function useInterfaceSupport(
    contractAddress: `0x${string}`,
    chainId: number,
    interfaces?: InterfaceName[]
): InterfaceSupportResult {
    const isChainSupported = supportedChains.some((chain) => chain.id === chainId)
    const supportedChainId = isChainSupported ? (chainId as SupportedChainId) : undefined

    // Use all interfaces if none specified
    const interfacesToCheck = interfaces ?? ALL_INTERFACE_NAMES

    // Build contract read configs for each interface
    const contracts = useMemo(() => {
        return interfacesToCheck.map((interfaceName) => ({
            address: contractAddress,
            abi: erc165Abi,
            functionName: "supportsInterface" as const,
            args: [INTERFACE_IDS[interfaceName]] as const,
            chainId: supportedChainId,
        }))
    }, [interfacesToCheck, contractAddress, supportedChainId])

    const { data, isLoading } = useReadContracts({
        contracts,
        query: {
            enabled: isChainSupported,
        },
    })

    // Build array of supported interface names from the results
    const supportedInterfaces = useMemo(() => {
        const result: InterfaceName[] = []

        if (data) {
            interfacesToCheck.forEach((interfaceName, index) => {
                const queryResult = data[index]
                // Check if the result is successful and truthy
                if (queryResult?.status === "success" && Boolean(queryResult.result)) {
                    result.push(interfaceName)
                }
            })
        }

        return result
    }, [data, interfacesToCheck])

    // Get ABIs for the supported interfaces
    const abis = useMemo(
        () => getAbisForSupportedInterfaces(supportedInterfaces),
        [supportedInterfaces]
    )

    return { isLoading, supportedInterfaces, abis }
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
