import { useReadContract } from "wagmi"
import type { Address } from "viem"
import { iEigenServiceManagerAbi } from "@/generated/abis"
import { supportedChains } from "@/lib/wagmi"

type SupportedChainId = (typeof supportedChains)[number]["id"]

/**
 * Hook to query whitelisted strategies from a service manager
 */
export function useWhitelistedStrategies(
    serviceManagerAddress: string | undefined,
    chainId: SupportedChainId | undefined
) {
    const {
        data: strategies,
        isLoading,
        refetch,
    } = useReadContract({
        address: serviceManagerAddress as Address,
        abi: iEigenServiceManagerAbi,
        functionName: "whitelistedStrategies",
        chainId,
        query: {
            enabled: !!serviceManagerAddress && !!chainId,
        },
    })

    return {
        strategies: strategies as Address[] | undefined,
        isLoading,
        refetch,
    }
}
