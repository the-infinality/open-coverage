import { useState, useMemo } from "react"
import { useReadContract } from "wagmi"
import type { Address } from "viem"
import { isAddress } from "viem"
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
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

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

const CUSTOM_ADDRESS_VALUE = "__custom__" as const

export interface StrategySelectProps {
    value: string
    onValueChange: (value: string) => void
    serviceManagerAddress: string | undefined
    chainId: SupportedChainId | undefined
    placeholder?: string
    disabled?: boolean
    /** When true, user can type or paste a strategy address instead of only selecting from whitelist. Default true. */
    allowManualEntry?: boolean
}

/**
 * Reusable strategy select for choosing whitelisted strategies from an Eigen service manager.
 * When allowManualEntry is true, users can also type or paste a strategy address.
 */
export function StrategySelect({
    value,
    onValueChange,
    serviceManagerAddress,
    chainId,
    placeholder,
    disabled,
    allowManualEntry = true,
}: StrategySelectProps) {
    const { strategies: whitelistedStrategies, isLoading: isLoadingStrategies } =
        useWhitelistedStrategies(serviceManagerAddress, chainId)

    const isValueWhitelisted =
        !!value &&
        !!whitelistedStrategies?.length &&
        whitelistedStrategies.some((a) => a.toLowerCase() === value.toLowerCase())

    const [customModeFlag, setCustomModeFlag] = useState(false)
    const isCustomMode = useMemo(
        () => customModeFlag && !isValueWhitelisted,
        [customModeFlag, isValueWhitelisted]
    )

    const selectValue = isCustomMode ? CUSTOM_ADDRESS_VALUE : isValueWhitelisted ? value : undefined

    const handleSelectChange = (v: string) => {
        if (v === CUSTOM_ADDRESS_VALUE) {
            setCustomModeFlag(true)
            onValueChange("")
        } else {
            setCustomModeFlag(false)
            onValueChange(v)
        }
    }

    const showCustomInput = allowManualEntry && isCustomMode

    return (
        <div className="space-y-2">
            <Select
                value={selectValue}
                onValueChange={handleSelectChange}
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
                            <StrategySelectItem
                                key={address}
                                address={address}
                                chainId={chainId}
                            />
                        ))
                    )}
                    {allowManualEntry && (
                        <SelectItem value={CUSTOM_ADDRESS_VALUE} className="font-mono">
                            Custom address...
                        </SelectItem>
                    )}
                </SelectContent>
            </Select>
            {showCustomInput && (
                <div className="space-y-1.5">
                    <Label className="text-xs text-muted-foreground">Strategy address</Label>
                    <Input
                        className="font-mono"
                        placeholder="0x..."
                        value={value}
                        onChange={(e) => onValueChange(e.target.value.trim())}
                        disabled={disabled}
                    />
                    {value && !isAddress(value) && (
                        <p className="text-xs text-destructive">Enter a valid Ethereum address</p>
                    )}
                </div>
            )}
        </div>
    )
}
