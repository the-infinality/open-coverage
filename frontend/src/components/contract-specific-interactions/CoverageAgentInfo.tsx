import { useMemo, useState, useEffect, useRef } from "react"
import { type Address } from "viem"
import { RefreshCw, Loader2, Plus, CheckCircle2 } from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iCoverageAgentAbi } from "@/generated/abis"
import { ContractCard } from "@/components/ContractCard"
import { CoverageProviderSelect } from "@/components/ContractSelects"
import {
    useAvailableCoverageProviders,
    getSelectedProvider,
} from "@/hooks/use-chain-filtered-contracts"
import { useContracts } from "@/hooks/use-contracts"
import { supportedChains } from "@/lib/wagmi"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface CoverageAgentInfoProps {
    contract: CoverageContract
}

export function CoverageAgentInfo({ contract }: CoverageAgentInfoProps) {
    const { contracts } = useContracts()
    const [selectedProviderId, setSelectedProviderId] = useState<string>("")

    // Check if chainId is supported
    const isChainSupported = supportedChains.some((chain) => chain.id === contract.chainId)
    const supportedChainId = isChainSupported ? (contract.chainId as SupportedChainId) : undefined

    const {
        data: coverageProviders,
        isLoading,
        isError,
        refetch,
    } = useReadContract({
        address: contract.address,
        abi: iCoverageAgentAbi,
        functionName: "registeredCoverageProviders",
        chainId: supportedChainId,
        query: {
            enabled: isChainSupported,
        },
    })

    // Write contract hook for registering providers
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    // Track previous success state to detect new success
    const prevSuccessRef = useRef(false)

    // Refetch providers after successful registration
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            refetch()
            // Reset selection after successful registration
            // Using a timeout to avoid cascading renders
            const timeoutId = setTimeout(() => {
                setSelectedProviderId("")
            }, 0)
            return () => clearTimeout(timeoutId)
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, refetch])

    // Create a map of saved contracts by address for quick lookup
    const savedContractsMap = useMemo(() => {
        const map = new Map<string, CoverageContract>()
        contracts.forEach((c) => {
            const key = `${c.chainId}-${c.address.toLowerCase()}`
            map.set(key, c)
        })
        return map
    }, [contracts])

    // Map registered provider addresses to saved contracts
    const registeredProviders = useMemo(() => {
        if (!coverageProviders) return []
        return (coverageProviders as Address[])
            .map((addr) => {
                const key = `${contract.chainId}-${addr.toLowerCase()}`
                return savedContractsMap.get(key)
            })
            .filter((c): c is CoverageContract => !!c)
    }, [coverageProviders, savedContractsMap, contract.chainId])

    // Extract IDs for exclusion
    const registeredProviderIds = useMemo(
        () => registeredProviders.map((p) => p.id),
        [registeredProviders]
    )

    // Get available providers (excluding already registered ones)
    const { availableProviders } = useAvailableCoverageProviders(
        contract.chainId,
        registeredProviderIds
    )

    // Get the selected provider contract
    const selectedProvider = getSelectedProvider(selectedProviderId, availableProviders)

    const handleRegisterProvider = () => {
        if (!selectedProvider) {
            toast.error("Please select a coverage provider")
            return
        }

        writeContract(
            {
                address: contract.address,
                abi: iCoverageAgentAbi,
                functionName: "registerCoverageProvider",
                args: [selectedProvider.address as `0x${string}`],
                chainId: supportedChainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center justify-between">
                    <div>
                        <CardTitle>Registered Coverage Providers</CardTitle>
                        <CardDescription>
                            Coverage providers registered with this agent
                        </CardDescription>
                    </div>
                    <Button
                        variant="outline"
                        size="sm"
                        onClick={() => refetch()}
                        disabled={isLoading}
                    >
                        {isLoading ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <RefreshCw className="mr-2 size-4" />
                        )}
                        Refresh
                    </Button>
                </div>
            </CardHeader>
            <CardContent className="space-y-6">
                {/* Registration Section */}
                <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
                    <div className="flex-1">
                        <CoverageProviderSelect
                            value={selectedProviderId}
                            onValueChange={setSelectedProviderId}
                            chainId={contract.chainId}
                            excludeIds={registeredProviderIds}
                            disabled={isPending || isConfirming}
                        />
                    </div>
                    <Button
                        onClick={handleRegisterProvider}
                        disabled={
                            !selectedProvider ||
                            isPending ||
                            isConfirming ||
                            availableProviders.length === 0
                        }
                    >
                        {isPending || isConfirming ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <Plus className="mr-2 size-4" />
                        )}
                        {isPending ? "Confirming..." : isConfirming ? "Registering..." : "Register"}
                    </Button>
                </div>

                {isSuccess && (
                    <p className="flex items-center gap-2 text-sm text-green-600">
                        <CheckCircle2 className="size-4" />
                        Coverage provider registered successfully!
                    </p>
                )}

                {/* Providers List */}
                {isLoading && registeredProviders.length === 0 ? (
                    <div className="flex items-center justify-center py-8">
                        <Loader2 className="size-6 animate-spin text-muted-foreground" />
                    </div>
                ) : isError ? (
                    <div className="py-8 text-center text-sm text-destructive">
                        Failed to fetch coverage providers
                    </div>
                ) : registeredProviders.length === 0 ? (
                    <div className="py-8 text-center text-sm text-muted-foreground">
                        No coverage providers registered yet
                    </div>
                ) : (
                    <ScrollArea className="h-fit max-h-[400px]">
                        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
                            {registeredProviders.map((provider) => (
                                <ContractCard key={provider.id} contract={provider} />
                            ))}
                        </div>
                    </ScrollArea>
                )}
            </CardContent>
        </Card>
    )
}
