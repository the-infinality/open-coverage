import { useReadContract } from "wagmi"
import type { Address } from "viem"
import { iEigenServiceManagerAbi } from "@/generated/abis"
import { iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"

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

/**
 * Strategy select item that displays strategy address and underlying token symbol
 */
function StrategySelectItem({
    address,
    chainId,
}: {
    address: Address
    chainId: SupportedChainId | undefined
}) {
    const { data: underlyingToken } = useReadContract({
        address,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    const { data: tokenSymbol } = useReadContract({
        address: underlyingToken as Address,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    return (
        <SelectItem value={address} className="font-mono">
            <div className="flex flex-col gap-0.5 items-start">
                <div className="font-sans font-medium">{tokenSymbol || "Loading..."}</div>
                <div className="text-xs text-muted-foreground">
                    {address.slice(0, 10)}...{address.slice(-8)}
                </div>
            </div>
        </SelectItem>
    )
}

export interface StrategySelectProps {
    value: string
    onValueChange: (value: string) => void
    serviceManagerAddress: string | undefined
    chainId: SupportedChainId | undefined
    placeholder?: string
    disabled?: boolean
}

/**
 * Reusable strategy select for choosing whitelisted strategies from an Eigen service manager
 */
export function StrategySelect({
    value,
    onValueChange,
    serviceManagerAddress,
    chainId,
    placeholder,
    disabled,
}: StrategySelectProps) {
    const { strategies: whitelistedStrategies, isLoading: isLoadingStrategies } =
        useWhitelistedStrategies(serviceManagerAddress, chainId)

    return (
        <Select
            value={value}
            onValueChange={onValueChange}
            disabled={disabled || !serviceManagerAddress || isLoadingStrategies}
        >
            <SelectTrigger className="font-mono">
                <SelectValue
                    placeholder={
                        !serviceManagerAddress
                            ? "Select a service manager first..."
                            : isLoadingStrategies
                              ? "Loading strategies..."
                              : placeholder || "Select strategy..."
                    }
                />
            </SelectTrigger>
            <SelectContent>
                {!whitelistedStrategies || whitelistedStrategies.length === 0 ? (
                    <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                        No whitelisted strategies found
                    </div>
                ) : (
                    whitelistedStrategies.map((address) => (
                        <StrategySelectItem key={address} address={address} chainId={chainId} />
                    ))
                )}
            </SelectContent>
        </Select>
    )
}
