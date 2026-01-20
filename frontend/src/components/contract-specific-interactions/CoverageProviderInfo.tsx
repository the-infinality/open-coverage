import { useMemo, useState, useEffect, useRef, useCallback } from "react"
import { type Address, isAddress, encodeAbiParameters, formatUnits, decodeEventLog } from "viem"
import { RefreshCw, Loader2, Plus, CheckCircle2, Trash2, X, Layers } from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useConfig } from "wagmi"
import { readContract } from "wagmi/actions"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iEigenServiceManagerAbi, iCoverageProviderAbi } from "@/generated/abis"
import { iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import { useCheckCoverageProviderSupport } from "@/hooks/use-interface-support"
import {
    useChainFilteredContracts,
    getSelectedOperatorProxy,
    getSelectedCoverageAgent,
} from "@/hooks/use-chain-filtered-contracts"
import { OperatorProxySelect, CoverageAgentSelect } from "@/components/ContractSelects"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { OperatorProxiesManagement } from "@/components/contract-specific-interactions/OperatorProxiesManagement"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface CoverageProviderInfoProps {
    contract: CoverageContract
}

/**
 * Component to display and manage strategy details
 */
function StrategyDetails({
    strategyAddress,
    chainId,
}: {
    strategyAddress: Address
    chainId: SupportedChainId | undefined
}) {
    // Get underlying token address
    const { data: underlyingToken, isLoading: isLoadingToken } = useReadContract({
        address: strategyAddress,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!strategyAddress && !!chainId,
        },
    })

    // Get token details
    const { data: tokenName } = useReadContract({
        address: underlyingToken as Address,
        abi: ierc20Abi,
        functionName: "name",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
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

    const { data: tokenDecimals } = useReadContract({
        address: underlyingToken as Address,
        abi: ierc20Abi,
        functionName: "decimals",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    if (isLoadingToken) {
        return (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Loader2 className="size-3 animate-spin" />
                Loading strategy details...
            </div>
        )
    }

    return (
        <div className="space-y-2 rounded-lg border bg-muted/30 p-3">
            <div className="flex items-center justify-between">
                <span className="text-xs text-muted-foreground">Strategy</span>
                <CopyableAddress address={strategyAddress} />
            </div>
            {underlyingToken && (
                <>
                    <Separator />
                    <div className="grid gap-2 text-sm">
                        <div className="flex items-center justify-between">
                            <span className="text-muted-foreground">Underlying Token</span>
                            <CopyableAddress address={underlyingToken as Address} />
                        </div>
                        {tokenName && tokenSymbol && (
                            <div className="flex items-center justify-between">
                                <span className="text-muted-foreground">Token</span>
                                <span className="font-medium">
                                    {tokenName} ({tokenSymbol})
                                </span>
                            </div>
                        )}
                        {tokenDecimals !== undefined && (
                            <div className="flex items-center justify-between">
                                <span className="text-muted-foreground">Decimals</span>
                                <span className="font-mono">{tokenDecimals}</span>
                            </div>
                        )}
                    </div>
                </>
            )}
        </div>
    )
}

/**
 * Whitelisted strategy item with remove functionality
 */
function WhitelistedStrategyItem({
    strategyAddress,
    chainId,
    contractAddress,
    onRemoveSuccess,
}: {
    strategyAddress: Address
    chainId: SupportedChainId | undefined
    contractAddress: Address
    onRemoveSuccess: () => void
}) {
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
        hash,
    })

    const prevSuccessRef = useRef(false)

    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            onRemoveSuccess()
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, onRemoveSuccess])

    const handleRemove = () => {
        writeContract(
            {
                address: contractAddress,
                abi: iEigenServiceManagerAbi,
                functionName: "setStrategyWhitelist",
                args: [strategyAddress, false],
                chainId,
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
        <div className="space-y-2">
            <div className="flex items-start justify-between gap-2">
                <div className="flex-1">
                    <StrategyDetails strategyAddress={strategyAddress} chainId={chainId} />
                </div>
                <Button
                    variant="outline"
                    size="sm"
                    onClick={handleRemove}
                    disabled={isPending || isConfirming}
                    className="shrink-0"
                >
                    {isPending || isConfirming ? (
                        <Loader2 className="size-4 animate-spin" />
                    ) : (
                        <Trash2 className="size-4" />
                    )}
                </Button>
            </div>
        </div>
    )
}

// Refundable enum values
const REFUNDABLE_OPTIONS = [
    { value: "0", label: "None", description: "No reward refund on liquidation" },
    {
        value: "1",
        label: "Time Weighted",
        description: "Refund based on time position has been open",
    },
    {
        value: "2",
        label: "Full",
        description: "Full refund of reward on liquidation",
    },
]

interface StrategyAssetInfo {
    strategyAddress: Address
    assetAddress: Address | null
    tokenName: string | null
    tokenSymbol: string | null
    isLoading: boolean
}

/**
 * Hook to fetch a single strategy's underlying token info
 */
function useStrategyAssetInfo(
    strategyAddress: Address | undefined,
    chainId: SupportedChainId | undefined
): StrategyAssetInfo | null {
    const { data: underlyingToken, isLoading: isLoadingToken } = useReadContract({
        address: strategyAddress,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!strategyAddress && !!chainId,
        },
    })

    const { data: tokenName, isLoading: isLoadingName } = useReadContract({
        address: underlyingToken as Address,
        abi: ierc20Abi,
        functionName: "name",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    const { data: tokenSymbol, isLoading: isLoadingSymbol } = useReadContract({
        address: underlyingToken as Address,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    if (!strategyAddress) return null

    return {
        strategyAddress,
        assetAddress: underlyingToken as Address | null,
        tokenName: tokenName as string | null,
        tokenSymbol: tokenSymbol as string | null,
        isLoading: isLoadingToken || isLoadingName || isLoadingSymbol,
    }
}

/**
 * Component to render a single strategy asset option in a select
 */
function StrategyAssetOption({
    strategyAddress,
    chainId,
}: {
    strategyAddress: Address
    chainId: SupportedChainId | undefined
}) {
    const info = useStrategyAssetInfo(strategyAddress, chainId)

    if (!info) return null

    if (info.isLoading) {
        return (
            <span className="flex items-center gap-2">
                <Loader2 className="size-3 animate-spin" />
                Loading...
            </span>
        )
    }

    return (
        <div className="flex flex-col gap-0.5 items-start">
            <div className="font-medium">
                {info.tokenName && info.tokenSymbol
                    ? `${info.tokenName} (${info.tokenSymbol})`
                    : info.assetAddress
                      ? `${info.assetAddress.slice(0, 10)}...${info.assetAddress.slice(-8)}`
                      : "Unknown Asset"}
            </div>
            <div className="text-xs text-muted-foreground">
                Strategy: {strategyAddress.slice(0, 10)}...{strategyAddress.slice(-8)}
            </div>
        </div>
    )
}

/**
 * Strategy Asset Select dropdown component
 */
function StrategyAssetSelect({
    value,
    onValueChange,
    strategies,
    chainId,
    disabled,
}: {
    value: string
    onValueChange: (strategyAddress: string) => void
    strategies: Address[]
    chainId: SupportedChainId | undefined
    disabled?: boolean
}) {
    return (
        <div className="space-y-2">
            <Label>Coverage Asset</Label>
            <Select value={value} onValueChange={onValueChange} disabled={disabled}>
                <SelectTrigger className="font-mono">
                    <SelectValue placeholder="Select asset from whitelisted strategies..." />
                </SelectTrigger>
                <SelectContent>
                    {strategies.length === 0 ? (
                        <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                            No whitelisted strategies available.
                            <br />
                            Add strategies to the whitelist first.
                        </div>
                    ) : (
                        strategies.map((strategyAddr) => (
                            <SelectItem
                                key={strategyAddr}
                                value={strategyAddr}
                                className="font-mono"
                            >
                                <StrategyAssetOption
                                    strategyAddress={strategyAddr}
                                    chainId={chainId}
                                />
                            </SelectItem>
                        ))
                    )}
                </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
                Select the asset to cover (derived from whitelisted strategies)
            </p>
        </div>
    )
}

interface CoveragePositionData {
    coverageAgent: Address
    minRate: number
    maxDuration: bigint
    expiryTimestamp: bigint
    asset: Address
    refundable: number
    slashCoordinator: Address
}

/**
 * Display a single position with close functionality
 */
function PositionItem({
    positionId,
    providerAddress,
    chainId,
    onCloseSuccess,
    onRemove,
}: {
    positionId: number
    providerAddress: Address
    chainId: SupportedChainId | undefined
    onCloseSuccess: () => void
    onRemove: () => void
}) {
    const { data: position, isLoading } = useReadContract({
        address: providerAddress,
        abi: iCoverageProviderAbi,
        functionName: "position",
        args: [BigInt(positionId)],
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
        hash,
    })

    const prevSuccessRef = useRef(false)

    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            toast.success("Position closed successfully")
            onCloseSuccess()
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, onCloseSuccess])

    const handleClose = () => {
        writeContract(
            {
                address: providerAddress,
                abi: iCoverageProviderAbi,
                functionName: "closePosition",
                args: [BigInt(positionId)],
                chainId,
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

    if (isLoading) {
        return (
            <div className="flex items-center gap-2 p-3 rounded-lg border">
                <Loader2 className="size-4 animate-spin" />
                <span className="text-sm text-muted-foreground">
                    Loading position #{positionId}...
                </span>
            </div>
        )
    }

    const positionData = position as CoveragePositionData | undefined
    const isExpired =
        positionData && BigInt(positionData.expiryTimestamp) < BigInt(Math.floor(Date.now() / 1000))
    const expiryDate = positionData ? new Date(Number(positionData.expiryTimestamp) * 1000) : null

    return (
        <div className="rounded-lg border p-4 space-y-3">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <Badge variant="outline">Position #{positionId}</Badge>
                    {isExpired && <Badge variant="destructive">Expired</Badge>}
                </div>
                <div className="flex items-center gap-2">
                    <Button
                        variant="outline"
                        size="sm"
                        onClick={handleClose}
                        disabled={isPending || isConfirming}
                    >
                        {isPending || isConfirming ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <X className="mr-2 size-4" />
                        )}
                        Close Position
                    </Button>
                    <Button variant="ghost" size="sm" onClick={onRemove} title="Remove from list">
                        <Trash2 className="size-4" />
                    </Button>
                </div>
            </div>

            {positionData && (
                <div className="grid gap-2 text-sm">
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Coverage Agent</span>
                        <CopyableAddress address={positionData.coverageAgent} />
                    </div>
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Asset</span>
                        <CopyableAddress address={positionData.asset} />
                    </div>
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Min Rate</span>
                        <span className="font-mono">{positionData.minRate / 100}%</span>
                    </div>
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Max Duration</span>
                        <span className="font-mono">
                            {formatUnits(BigInt(positionData.maxDuration), 0)} seconds
                        </span>
                    </div>
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Expires</span>
                        <span className="font-mono text-xs">{expiryDate?.toLocaleString()}</span>
                    </div>
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Refundable</span>
                        <span>
                            {REFUNDABLE_OPTIONS[positionData.refundable]?.label || "Unknown"}
                        </span>
                    </div>
                </div>
            )}
        </div>
    )
}

/**
 * Operator Position Management component - shown for all provider types
 */
function OperatorPositionManagement({
    contract,
    chainId,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
}) {
    // State for form inputs
    const [selectedOperatorId, setSelectedOperatorId] = useState("")
    const [selectedCoverageAgentId, setSelectedCoverageAgentId] = useState("")
    const [minRate, setMinRate] = useState("500") // 5% default (basis points)
    const [maxDuration, setMaxDuration] = useState("31536000") // 1 year in seconds
    const [expiryDays, setExpiryDays] = useState("365")
    const [selectedStrategyAddress, setSelectedStrategyAddress] = useState("")
    const [refundable, setRefundable] = useState("0")
    const [slashCoordinator, setSlashCoordinator] = useState("")
    const [positionIds, setPositionIds] = useState<number[]>([])
    const [newPositionId, setNewPositionId] = useState("")
    const [isCheckingPosition, setIsCheckingPosition] = useState(false)

    // Get wagmi config for imperative contract reads
    const config = useConfig()

    // Get operator proxies and coverage agents from saved contracts
    const { operatorProxies, coverageAgents } = useChainFilteredContracts(contract.chainId)
    const selectedOperator = getSelectedOperatorProxy(selectedOperatorId, operatorProxies)
    const selectedCoverageAgent = getSelectedCoverageAgent(selectedCoverageAgentId, coverageAgents)

    // Fetch whitelisted strategies from the provider
    const { data: whitelistedStrategies, isLoading: isLoadingStrategies } = useReadContract({
        address: contract.address,
        abi: iEigenServiceManagerAbi,
        functionName: "whitelistedStrategies",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    const strategies = useMemo(() => {
        if (!whitelistedStrategies) return []
        return [...(whitelistedStrategies as Address[])]
    }, [whitelistedStrategies])

    // Get the underlying asset for the selected strategy
    const selectedStrategyInfo = useStrategyAssetInfo(
        selectedStrategyAddress ? (selectedStrategyAddress as Address) : undefined,
        chainId
    )

    // Derived asset address from the selected strategy
    const assetAddress = selectedStrategyInfo?.assetAddress || ""

    // Write contract hooks
    const { writeContract, isPending, data: hash } = useWriteContract()
    const {
        isLoading: isConfirming,
        isSuccess,
        data: receipt,
    } = useWaitForTransactionReceipt({ hash })

    // Track previous success to avoid duplicate processing
    const prevCreateSuccessRef = useRef(false)

    // Parse position ID from transaction logs when position is created successfully
    useEffect(() => {
        if (isSuccess && receipt && !prevCreateSuccessRef.current) {
            try {
                // Find the PositionCreated event in the logs
                for (const log of receipt.logs) {
                    try {
                        const decoded = decodeEventLog({
                            abi: iCoverageProviderAbi,
                            data: log.data,
                            topics: log.topics,
                        })

                        if (
                            decoded.eventName === "PositionCreated" &&
                            decoded.args &&
                            "positionId" in decoded.args
                        ) {
                            const newPositionId = Number(decoded.args.positionId)
                            if (!positionIds.includes(newPositionId)) {
                                setPositionIds((prev) => [...prev, newPositionId])
                                toast.success(
                                    `Position #${newPositionId} created and added to view`
                                )
                            }
                            break
                        }
                    } catch {
                        // Not the event we're looking for, continue
                    }
                }
            } catch (error) {
                console.error("Error parsing position creation logs:", error)
            }
        }
        prevCreateSuccessRef.current = isSuccess
    }, [isSuccess, receipt, positionIds])

    // Reset form after successful transaction
    const resetForm = () => {
        setMinRate("500")
        setMaxDuration("31536000")
        setExpiryDays("365")
        setSelectedStrategyAddress("")
        setRefundable("0")
        setSlashCoordinator("")
    }

    const isValidForm = useMemo(() => {
        return (
            selectedOperator &&
            selectedCoverageAgent &&
            selectedStrategyAddress &&
            assetAddress &&
            isAddress(assetAddress) &&
            minRate &&
            maxDuration &&
            expiryDays &&
            (slashCoordinator === "" || isAddress(slashCoordinator))
        )
    }, [
        selectedOperator,
        selectedCoverageAgent,
        selectedStrategyAddress,
        assetAddress,
        minRate,
        maxDuration,
        expiryDays,
        slashCoordinator,
    ])

    const handleCreatePosition = () => {
        if (!isValidForm || !selectedCoverageAgent || !selectedOperator || !assetAddress) {
            toast.error("Please fill in all required fields")
            return
        }

        // Calculate expiry timestamp
        const expiryTimestamp = BigInt(
            Math.floor(Date.now() / 1000) + Number(expiryDays) * 24 * 60 * 60
        )

        // Encode additional data for EigenLayer providers
        // This matches the CreatePositionAddtionalData struct: { address operator; address strategy; }
        // The operator is the EigenOperatorProxy contract address that acts as the operator in EigenLayer
        // The strategy is the selected whitelisted strategy address
        const additionalData = encodeAbiParameters(
            [
                { type: "address", name: "operator" },
                { type: "address", name: "strategy" },
            ],
            [selectedOperator.address, selectedStrategyAddress as Address]
        )

        // CoveragePosition struct
        const positionData = {
            coverageAgent: selectedCoverageAgent.address,
            minRate: Number(minRate),
            maxDuration: BigInt(maxDuration),
            expiryTimestamp,
            asset: assetAddress,
            refundable: Number(refundable),
            slashCoordinator: (slashCoordinator ||
                "0x0000000000000000000000000000000000000000") as Address,
        }

        console.log("Creating position with data:", [positionData, additionalData])
        writeContract(
            {
                address: contract.address,
                abi: iCoverageProviderAbi,
                functionName: "createPosition",
                args: [positionData, additionalData],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                    resetForm()
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    const handleAddPositionId = async () => {
        const id = Number(newPositionId)
        if (isNaN(id) || id < 0) {
            toast.error("Please enter a valid position ID")
            return
        }
        if (positionIds.includes(id)) {
            toast.error("Position already loaded")
            return
        }
        if (!chainId) {
            toast.error("Chain not supported")
            return
        }

        setIsCheckingPosition(true)
        try {
            // Check if position exists by trying to read it
            const position = await readContract(config, {
                address: contract.address,
                abi: iCoverageProviderAbi,
                functionName: "position",
                args: [BigInt(id)],
                chainId,
            })

            // Check if the position has a valid coverage agent (non-zero address indicates it exists)
            const positionData = position as { coverageAgent: Address } | undefined
            if (
                !positionData ||
                positionData.coverageAgent === "0x0000000000000000000000000000000000000000"
            ) {
                toast.error(`Position #${id} does not exist`)
                return
            }

            setPositionIds([...positionIds, id])
            setNewPositionId("")
            toast.success(`Position #${id} loaded`)
        } catch {
            toast.error(`Position #${id} does not exist or could not be fetched`)
        } finally {
            setIsCheckingPosition(false)
        }
    }

    const handleRemovePositionId = (id: number) => {
        setPositionIds(positionIds.filter((p) => p !== id))
    }

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center justify-between">
                    <div>
                        <CardTitle className="flex items-center gap-2">
                            <Layers className="size-5" />
                            Operator Position Management
                        </CardTitle>
                        <CardDescription>
                            Create and manage coverage positions through operator agents
                        </CardDescription>
                    </div>
                </div>
            </CardHeader>
            <CardContent className="space-y-6">
                {/* Create Position Section */}
                <div className="space-y-4">
                    <div className="rounded-lg bg-muted/50 p-3">
                        <h4 className="text-sm font-medium">Create New Position</h4>
                        <p className="text-xs text-muted-foreground mt-1">
                            Select an operator agent and configure the coverage position parameters
                        </p>
                    </div>

                    <div className="grid gap-4 md:grid-cols-2">
                        {/* Operator Agent Selection */}
                        <div className="space-y-2">
                            <Label>Operator Agent</Label>
                            <OperatorProxySelect
                                selectedContractId={selectedOperatorId}
                                onSelectedContractIdChange={setSelectedOperatorId}
                                contracts={operatorProxies}
                                disabled={isPending || isConfirming}
                            />
                            <p className="text-xs text-muted-foreground">
                                The operator agent that will provide coverage
                            </p>
                        </div>

                        {/* Coverage Agent Selection */}
                        <div className="space-y-2">
                            <Label>Coverage Agent</Label>
                            <CoverageAgentSelect
                                selectedContractId={selectedCoverageAgentId}
                                onSelectedContractIdChange={setSelectedCoverageAgentId}
                                contracts={coverageAgents}
                                disabled={isPending || isConfirming}
                            />
                            <p className="text-xs text-muted-foreground">
                                The coverage agent that will receive protection
                            </p>
                        </div>
                    </div>

                    {/* Strategy/Asset Selection */}
                    <div className="space-y-2">
                        {isLoadingStrategies ? (
                            <div className="flex items-center gap-2 text-sm text-muted-foreground">
                                <Loader2 className="size-4 animate-spin" />
                                Loading whitelisted strategies...
                            </div>
                        ) : (
                            <StrategyAssetSelect
                                value={selectedStrategyAddress}
                                onValueChange={setSelectedStrategyAddress}
                                strategies={strategies}
                                chainId={chainId}
                                disabled={isPending || isConfirming}
                            />
                        )}

                        {/* Show derived addresses when strategy is selected */}
                        {selectedStrategyAddress &&
                            selectedStrategyInfo &&
                            !selectedStrategyInfo.isLoading && (
                                <div className="rounded-lg border bg-muted/30 p-3 space-y-2 text-sm">
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Strategy</span>
                                        <CopyableAddress
                                            address={selectedStrategyAddress as Address}
                                        />
                                    </div>
                                    {selectedStrategyInfo.assetAddress && (
                                        <div className="flex items-center justify-between">
                                            <span className="text-muted-foreground">
                                                Underlying Asset
                                            </span>
                                            <CopyableAddress
                                                address={selectedStrategyInfo.assetAddress}
                                            />
                                        </div>
                                    )}
                                    {selectedStrategyInfo.tokenName &&
                                        selectedStrategyInfo.tokenSymbol && (
                                            <div className="flex items-center justify-between">
                                                <span className="text-muted-foreground">Token</span>
                                                <span className="font-medium">
                                                    {selectedStrategyInfo.tokenName} (
                                                    {selectedStrategyInfo.tokenSymbol})
                                                </span>
                                            </div>
                                        )}
                                </div>
                            )}
                    </div>

                    <div className="grid gap-4 md:grid-cols-3">
                        {/* Min Rate */}
                        <div className="space-y-2">
                            <Label htmlFor="minRate">Min Rate (basis points)</Label>
                            <Input
                                id="minRate"
                                type="number"
                                placeholder="500"
                                value={minRate}
                                onChange={(e) => setMinRate(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming}
                            />
                            <p className="text-xs text-muted-foreground">
                                {Number(minRate) / 100}% per annum
                            </p>
                        </div>

                        {/* Max Duration */}
                        <div className="space-y-2">
                            <Label htmlFor="maxDuration">Max Duration (seconds)</Label>
                            <Input
                                id="maxDuration"
                                type="number"
                                placeholder="31536000"
                                value={maxDuration}
                                onChange={(e) => setMaxDuration(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming}
                            />
                            <p className="text-xs text-muted-foreground">
                                {Math.round(Number(maxDuration) / 86400)} days
                            </p>
                        </div>

                        {/* Expiry Days */}
                        <div className="space-y-2">
                            <Label htmlFor="expiryDays">Expiry (days from now)</Label>
                            <Input
                                id="expiryDays"
                                type="number"
                                placeholder="365"
                                value={expiryDays}
                                onChange={(e) => setExpiryDays(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming}
                            />
                        </div>
                    </div>

                    <div className="grid gap-4 md:grid-cols-2">
                        {/* Refundable */}
                        <div className="space-y-2">
                            <Label>Refund Policy</Label>
                            <Select
                                value={refundable}
                                onValueChange={setRefundable}
                                disabled={isPending || isConfirming}
                            >
                                <SelectTrigger>
                                    <SelectValue placeholder="Select refund policy..." />
                                </SelectTrigger>
                                <SelectContent>
                                    {REFUNDABLE_OPTIONS.map((option) => (
                                        <SelectItem key={option.value} value={option.value}>
                                            <span className="flex flex-col gap-0.5">
                                                <span className="font-medium">{option.label}</span>
                                                <span className="text-xs text-muted-foreground">
                                                    {option.description}
                                                </span>
                                            </span>
                                        </SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>

                        {/* Slash Coordinator */}
                        <div className="space-y-2">
                            <Label htmlFor="slashCoordinator">Slash Coordinator (optional)</Label>
                            <Input
                                id="slashCoordinator"
                                placeholder="0x... (leave empty for instant slash)"
                                value={slashCoordinator}
                                onChange={(e) => setSlashCoordinator(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming}
                            />
                            {slashCoordinator && !isAddress(slashCoordinator) && (
                                <p className="text-xs text-destructive">Invalid address</p>
                            )}
                        </div>
                    </div>

                    <Button
                        onClick={handleCreatePosition}
                        disabled={!isValidForm || isPending || isConfirming}
                        className="w-full"
                    >
                        {isPending || isConfirming ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <Plus className="mr-2 size-4" />
                        )}
                        {isPending
                            ? "Confirm in wallet..."
                            : isConfirming
                              ? "Creating..."
                              : "Create Position"}
                    </Button>

                    {isSuccess && (
                        <p className="flex items-center gap-2 text-sm text-green-600">
                            <CheckCircle2 className="size-4" />
                            Position created successfully!
                        </p>
                    )}
                </div>

                <Separator />

                {/* View Positions Section */}
                <div className="space-y-4">
                    <div className="flex items-center justify-between">
                        <h4 className="text-sm font-medium">View Positions</h4>
                        <Badge variant="secondary">{positionIds.length} loaded</Badge>
                    </div>

                    <div className="flex gap-2">
                        <Input
                            placeholder="Enter position ID..."
                            value={newPositionId}
                            onChange={(e) => setNewPositionId(e.target.value)}
                            className="font-mono"
                            type="number"
                        />
                        <Button
                            variant="outline"
                            onClick={handleAddPositionId}
                            disabled={
                                !newPositionId || isNaN(Number(newPositionId)) || isCheckingPosition
                            }
                        >
                            {isCheckingPosition ? (
                                <Loader2 className="mr-2 size-4 animate-spin" />
                            ) : (
                                <Plus className="mr-2 size-4" />
                            )}
                            {isCheckingPosition ? "Checking..." : "Load"}
                        </Button>
                    </div>

                    {positionIds.length === 0 ? (
                        <div className="py-8 text-center text-sm text-muted-foreground">
                            Enter a position ID to view its details
                        </div>
                    ) : (
                        <ScrollArea className="h-fit">
                            <div className="space-y-3 max-h-[400px]">
                                {positionIds.map((positionId) => (
                                    <PositionItem
                                        key={positionId}
                                        positionId={positionId}
                                        providerAddress={contract.address}
                                        chainId={chainId}
                                        onCloseSuccess={() => handleRemovePositionId(positionId)}
                                        onRemove={() => handleRemovePositionId(positionId)}
                                    />
                                ))}
                            </div>
                        </ScrollArea>
                    )}
                </div>
            </CardContent>
        </Card>
    )
}

export function CoverageProviderInfo({ contract }: CoverageProviderInfoProps) {
    const [newStrategyAddress, setNewStrategyAddress] = useState("")

    // Check if chainId is supported
    const isChainSupported = supportedChains.some((chain) => chain.id === contract.chainId)
    const supportedChainId = isChainSupported ? (contract.chainId as SupportedChainId) : undefined

    // Check for IEigenServiceManager interface support via ERC-165
    const { isLoading: isCheckingInterface, supports } = useCheckCoverageProviderSupport(
        contract.address,
        contract.chainId,
        ["IEigenServiceManager"]
    )
    const isEigenProvider = supports.IEigenServiceManager

    // Get whitelisted strategies
    const {
        data: whitelistedStrategies,
        isLoading: isLoadingStrategies,
        isError,
        refetch,
    } = useReadContract({
        address: contract.address,
        abi: iEigenServiceManagerAbi,
        functionName: "whitelistedStrategies",
        chainId: supportedChainId,
        query: {
            enabled: isChainSupported && isEigenProvider,
        },
    })

    // Write contract hook for adding strategies
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
        hash,
    })

    // Track previous success state
    const prevSuccessRef = useRef(false)

    // Refetch after successful add
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            refetch()
            const timeoutId = setTimeout(() => {
                setNewStrategyAddress("")
            }, 0)
            return () => clearTimeout(timeoutId)
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, refetch])

    // Derive preview strategy from address input (no state needed)
    const previewStrategy = useMemo(() => {
        if (newStrategyAddress && isAddress(newStrategyAddress)) {
            return newStrategyAddress as Address
        }
        return null
    }, [newStrategyAddress])

    const strategies = useMemo(() => {
        if (!whitelistedStrategies) return []
        return [...(whitelistedStrategies as Address[])]
    }, [whitelistedStrategies])

    const isValidAddress = useMemo(() => {
        return newStrategyAddress && isAddress(newStrategyAddress)
    }, [newStrategyAddress])

    const isAlreadyWhitelisted = useMemo(() => {
        if (!isValidAddress || !strategies.length) return false
        return strategies.some((s) => s.toLowerCase() === newStrategyAddress.toLowerCase())
    }, [newStrategyAddress, strategies, isValidAddress])

    const handleAddStrategy = useCallback(() => {
        if (!isValidAddress) {
            toast.error("Please enter a valid strategy address")
            return
        }

        if (isAlreadyWhitelisted) {
            toast.error("Strategy is already whitelisted")
            return
        }

        writeContract(
            {
                address: contract.address,
                abi: iEigenServiceManagerAbi,
                functionName: "setStrategyWhitelist",
                args: [newStrategyAddress as `0x${string}`, true],
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
    }, [
        isValidAddress,
        isAlreadyWhitelisted,
        writeContract,
        contract.address,
        supportedChainId,
        newStrategyAddress,
    ])

    const eigenProvider = useMemo(() => {
        return isEigenProvider ? (
            <>
                <Separator />

                <h2 className="text-lg font-semibold">Eigen Service Manager Functionality</h2>

                {/* Operator Proxies Management - Deploy and manage EigenOperatorProxy contracts */}
                <OperatorProxiesManagement contract={contract} />

                {/* Strategy Whitelist Management Card - EigenLayer specific */}
                <Card>
                    <CardHeader>
                        <div className="flex items-center justify-between">
                            <div>
                                <CardTitle>Strategy Whitelist</CardTitle>
                                <CardDescription>
                                    Manage which EigenLayer strategies are whitelisted for this
                                    provider
                                </CardDescription>
                            </div>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => refetch()}
                                disabled={isLoadingStrategies}
                            >
                                {isLoadingStrategies ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="mr-2 size-4" />
                                )}
                                Refresh
                            </Button>
                        </div>
                    </CardHeader>
                    <CardContent className="space-y-6">
                        {/* Add Strategy Section */}
                        <div className="space-y-4">
                            <div className="rounded-lg bg-muted/50 p-3">
                                <h4 className="text-sm font-medium">Add Strategy to Whitelist</h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Enter an EigenLayer strategy address to whitelist. Strategy
                                    details will be shown below.
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="strategy-address">Strategy Address</Label>
                                <div className="flex gap-2">
                                    <Input
                                        id="strategy-address"
                                        placeholder="0x..."
                                        value={newStrategyAddress}
                                        onChange={(e) => setNewStrategyAddress(e.target.value)}
                                        className="font-mono"
                                        disabled={isPending || isConfirming}
                                    />
                                    <Button
                                        onClick={handleAddStrategy}
                                        disabled={
                                            !isValidAddress ||
                                            isAlreadyWhitelisted ||
                                            isPending ||
                                            isConfirming
                                        }
                                    >
                                        {isPending || isConfirming ? (
                                            <Loader2 className="mr-2 size-4 animate-spin" />
                                        ) : (
                                            <Plus className="mr-2 size-4" />
                                        )}
                                        {isPending
                                            ? "Confirm..."
                                            : isConfirming
                                              ? "Adding..."
                                              : "Add"}
                                    </Button>
                                </div>
                                {newStrategyAddress && !isValidAddress && (
                                    <p className="text-xs text-destructive">
                                        Please enter a valid Ethereum address
                                    </p>
                                )}
                                {isAlreadyWhitelisted && (
                                    <p className="text-xs text-amber-600">
                                        This strategy is already whitelisted
                                    </p>
                                )}
                            </div>

                            {/* Strategy Preview */}
                            {previewStrategy && !isAlreadyWhitelisted && (
                                <div className="space-y-2">
                                    <Label>Strategy Preview</Label>
                                    <StrategyDetails
                                        strategyAddress={previewStrategy}
                                        chainId={supportedChainId}
                                    />
                                </div>
                            )}

                            {isSuccess && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Strategy added to whitelist successfully!
                                </p>
                            )}
                        </div>

                        <Separator />

                        {/* Whitelisted Strategies List */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <h4 className="text-sm font-medium">Whitelisted Strategies</h4>
                                <Badge variant="secondary">{strategies.length} strategies</Badge>
                            </div>

                            {isLoadingStrategies && strategies.length === 0 ? (
                                <div className="flex items-center justify-center py-8">
                                    <Loader2 className="size-6 animate-spin text-muted-foreground" />
                                </div>
                            ) : isError ? (
                                <div className="py-8 text-center text-sm text-destructive">
                                    Failed to fetch whitelisted strategies
                                </div>
                            ) : strategies.length === 0 ? (
                                <div className="py-8 text-center text-sm text-muted-foreground">
                                    No strategies whitelisted yet
                                </div>
                            ) : (
                                <ScrollArea className="h-fit max-h-[500px]">
                                    <div className="space-y-4">
                                        {strategies.map((strategyAddress) => (
                                            <WhitelistedStrategyItem
                                                key={strategyAddress}
                                                strategyAddress={strategyAddress}
                                                chainId={supportedChainId}
                                                contractAddress={contract.address}
                                                onRemoveSuccess={() => refetch()}
                                            />
                                        ))}
                                    </div>
                                </ScrollArea>
                            )}
                        </div>
                    </CardContent>
                </Card>
            </>
        ) : null
    }, [
        isEigenProvider,
        contract,
        supportedChainId,
        isLoadingStrategies,
        newStrategyAddress,
        isPending,
        isConfirming,
        handleAddStrategy,
        isValidAddress,
        isAlreadyWhitelisted,
        previewStrategy,
        isSuccess,
        strategies,
        isError,
        refetch,
    ])

    // Show loading state while checking interface support
    if (isCheckingInterface) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle>Coverage Provider</CardTitle>
                    <CardDescription>Checking provider capabilities...</CardDescription>
                </CardHeader>
                <CardContent>
                    <div className="flex items-center justify-center py-8">
                        <Loader2 className="size-6 animate-spin text-muted-foreground" />
                    </div>
                </CardContent>
            </Card>
        )
    }

    return (
        <div className="space-y-6">
            {/* Operator Position Management - Available for all providers */}
            <OperatorPositionManagement contract={contract} chainId={supportedChainId} />
            {eigenProvider}
        </div>
    )
}
