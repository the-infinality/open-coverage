import { useState, useMemo, useEffect, useRef, useCallback } from "react"
import { type Address, type Abi, isAddress, parseUnits, formatUnits, decodeErrorResult, BaseError } from "viem"
import {
    RefreshCw,
    Loader2,
    CheckCircle2,
    ArrowRightLeft,
    Calculator,
    Settings,
    Plus,
    Coins,
} from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iAssetPriceOracleAndSwapperAbi } from "@/generated/abis"
import { iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { UniswapV3PoolInput } from "./UniswapV3PoolInput"

type SupportedChainId = (typeof supportedChains)[number]["id"]

// Combined ABI for error decoding
const combinedErrorAbi = [
    // IAssetPriceOracleAndSwapper errors
    { type: "error", inputs: [{ name: "assetA", type: "address" }, { name: "assetB", type: "address" }], name: "AssetPairAlreadyRegistered" },
    { type: "error", inputs: [{ name: "assetA", type: "address" }, { name: "assetB", type: "address" }], name: "AssetPairNotRegistered" },
    { type: "error", inputs: [], name: "InvalidSlippage" },
    { type: "error", inputs: [], name: "InvalidPriceStrategy" },
    { type: "error", inputs: [], name: "InvalidSwapEngine" },
    { type: "error", inputs: [], name: "OracleRequired" },
    { type: "error", inputs: [], name: "SwapFailed" },
    { type: "error", inputs: [], name: "SlippageExceeded" },
    // Diamond errors
    { type: "error", inputs: [], name: "NotContractOwner" },
    // Common errors
    { type: "error", inputs: [], name: "ZeroAddress" },
] as const

// Human-readable error messages
const errorMessages: Record<string, string> = {
    AssetPairAlreadyRegistered: "This asset pair is already registered.",
    AssetPairNotRegistered: "This asset pair is not registered.",
    InvalidSlippage: "The slippage value is invalid. Must be between 0.01% and 20%.",
    InvalidPriceStrategy: "Invalid price strategy selected.",
    InvalidSwapEngine: "Invalid swap engine address.",
    OracleRequired: "A price oracle is required for this price strategy.",
    SwapFailed: "The swap operation failed.",
    SlippageExceeded: "The swap would exceed the maximum slippage tolerance.",
    NotContractOwner: "Only the contract owner can perform this action.",
    ZeroAddress: "Cannot use zero address.",
}

/**
 * Decodes a contract error and returns a human-readable message
 */
function decodeContractError(error: unknown): string {
    if (error instanceof BaseError) {
        let currentError: unknown = error
        while (currentError) {
            if (
                typeof currentError === "object" &&
                currentError !== null &&
                "data" in currentError &&
                typeof (currentError as { data?: unknown }).data === "string"
            ) {
                const errorData = (currentError as { data: string }).data
                if (errorData && errorData.startsWith("0x") && errorData.length >= 10) {
                    try {
                        const decoded = decodeErrorResult({
                            abi: combinedErrorAbi as Abi,
                            data: errorData as `0x${string}`,
                        })
                        
                        const friendlyMessage = errorMessages[decoded.errorName]
                        if (friendlyMessage) {
                            if (decoded.args && decoded.args.length > 0) {
                                return `${friendlyMessage} (${decoded.args.join(", ")})`
                            }
                            return friendlyMessage
                        }
                        return `Contract error: ${decoded.errorName}`
                    } catch {
                        // Could not decode, continue
                    }
                }
            }
            currentError =
                typeof currentError === "object" && currentError !== null && "cause" in currentError
                    ? (currentError as { cause?: unknown }).cause
                    : null
        }
        
        const errorMessage = error.message || ""
        const revertMatch = errorMessage.match(/reverted with reason string '([^']+)'/)
        if (revertMatch) return revertMatch[1]
        
        const customErrorMatch = errorMessage.match(/reverted with custom error '([^'(]+)/)
        if (customErrorMatch) {
            const errorName = customErrorMatch[1]
            return errorMessages[errorName] || `Contract error: ${errorName}`
        }
        
        for (const [errorName, message] of Object.entries(errorMessages)) {
            if (errorMessage.includes(errorName)) return message
        }
    }
    
    const message = error instanceof Error ? error.message : String(error)
    return message.length > 200 ? message.slice(0, 200) + "..." : message
}

// Price strategy enum options
const PRICE_STRATEGY_OPTIONS = [
    { value: "0", label: "Oracle Only", description: "Only use the oracle to get the quote" },
    { value: "1", label: "Swapper Only", description: "Only use the swapper to get the quote" },
    {
        value: "2",
        label: "Swapper Verified",
        description: "Use the swapper to get the quote and verify with the oracle",
    },
    {
        value: "3",
        label: "Oracle Verified",
        description: "Use the oracle to get the quote and verify with the swapper",
    },
]

interface AssetPriceOracleAndSwapperInteractionProps {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    strategies: Address[]
    isLoadingStrategies: boolean
}

/**
 * Hook to fetch token info for an address
 */
function useTokenInfo(tokenAddress: Address | undefined, chainId: SupportedChainId | undefined) {
    const { data: tokenName, isLoading: isLoadingName } = useReadContract({
        address: tokenAddress,
        abi: ierc20Abi,
        functionName: "name",
        chainId,
        query: {
            enabled: !!tokenAddress && !!chainId,
        },
    })

    const { data: tokenSymbol, isLoading: isLoadingSymbol } = useReadContract({
        address: tokenAddress,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!tokenAddress && !!chainId,
        },
    })

    const { data: tokenDecimals, isLoading: isLoadingDecimals } = useReadContract({
        address: tokenAddress,
        abi: ierc20Abi,
        functionName: "decimals",
        chainId,
        query: {
            enabled: !!tokenAddress && !!chainId,
        },
    })

    return {
        tokenName: tokenName as string | undefined,
        tokenSymbol: tokenSymbol as string | undefined,
        tokenDecimals: tokenDecimals as number | undefined,
        isLoading: isLoadingName || isLoadingSymbol || isLoadingDecimals,
    }
}

/**
 * Hook to fetch strategy's underlying token
 */
function useStrategyUnderlyingToken(
    strategyAddress: Address | undefined,
    chainId: SupportedChainId | undefined
) {
    const { data: underlyingToken, isLoading } = useReadContract({
        address: strategyAddress,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!strategyAddress && !!chainId,
        },
    })

    return {
        underlyingToken: underlyingToken as Address | undefined,
        isLoading,
    }
}

/**
 * Strategy Asset Option component for dropdown display
 */
function StrategyAssetOption({
    strategyAddress,
    chainId,
}: {
    strategyAddress: Address
    chainId: SupportedChainId | undefined
}) {
    const { underlyingToken, isLoading: isLoadingToken } = useStrategyUnderlyingToken(
        strategyAddress,
        chainId
    )
    const {
        tokenName,
        tokenSymbol,
        isLoading: isLoadingInfo,
    } = useTokenInfo(underlyingToken, chainId)

    if (isLoadingToken || isLoadingInfo) {
        return (
            <div className="flex items-center gap-2">
                <Loader2 className="size-3 animate-spin" />
                Loading...
            </div>
        )
    }

    return (
        <div className="flex flex-col gap-0.5">
            <div className="font-medium">
                {tokenName && tokenSymbol
                    ? `${tokenName} (${tokenSymbol})`
                    : underlyingToken
                      ? `${underlyingToken.slice(0, 10)}...${underlyingToken.slice(-8)}`
                      : "Unknown Asset"}
            </div>
            <div className="text-xs text-muted-foreground">
                Strategy: {strategyAddress.slice(0, 10)}...{strategyAddress.slice(-8)}
            </div>
        </div>
    )
}

/**
 * Quote Results Display Component
 */
function QuoteResults({
    quote,
    verified,
    minAmountOut,
    maxAmountIn,
    assetASymbol,
    assetADecimals,
}: {
    quote?: bigint
    verified?: boolean
    minAmountOut?: bigint
    maxAmountIn?: bigint
    assetASymbol?: string
    assetADecimals?: number
}) {
    return (
        <div className="space-y-3 rounded-lg border bg-muted/30 p-4">
            <h4 className="font-medium text-sm">Quote Results</h4>
            <div className="grid gap-2 text-sm">
                {quote !== undefined && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Quote</span>
                        <div className="flex items-center gap-2">
                            <span className="font-mono">
                                {formatUnits(quote, assetADecimals || 18)}{" "}
                                {assetASymbol || "tokens"}
                            </span>
                            {verified !== undefined && (
                                <Badge variant={verified ? "default" : "secondary"}>
                                    {verified ? "Verified" : "Unverified"}
                                </Badge>
                            )}
                        </div>
                    </div>
                )}
                {minAmountOut !== undefined && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Min Amount Out</span>
                        <span className="font-mono">
                            {formatUnits(minAmountOut, assetADecimals || 18)}{" "}
                            {assetASymbol || "tokens"}
                        </span>
                    </div>
                )}
                {maxAmountIn !== undefined && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Max Amount In</span>
                        <span className="font-mono">
                            {formatUnits(maxAmountIn, assetADecimals || 18)}{" "}
                            {assetASymbol || "tokens"}
                        </span>
                    </div>
                )}
            </div>
        </div>
    )
}

/**
 * Asset Pair Info Display Component
 */
function AssetPairInfo({
    assetPair,
}: {
    assetPair: {
        assetA: Address
        assetB: Address
        swapEngine: Address
        poolInfo: `0x${string}`
        priceStrategy: number
        swapperAccuracy: number
        priceOracle: Address
    }
}) {
    const strategyLabel = PRICE_STRATEGY_OPTIONS[assetPair.priceStrategy]?.label || "Unknown"

    return (
        <div className="space-y-3 rounded-lg border bg-muted/30 p-4">
            <h4 className="font-medium text-sm">Asset Pair Configuration</h4>
            <div className="grid gap-2 text-sm">
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Asset A (Output)</span>
                    <CopyableAddress address={assetPair.assetA} />
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Asset B (Input)</span>
                    <CopyableAddress address={assetPair.assetB} />
                </div>
                <Separator />
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Swap Engine</span>
                    <CopyableAddress address={assetPair.swapEngine} />
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Price Strategy</span>
                    <Badge variant="outline">{strategyLabel}</Badge>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Swapper Accuracy</span>
                    <span className="font-mono">{assetPair.swapperAccuracy / 100}%</span>
                </div>
                {assetPair.priceOracle !== "0x0000000000000000000000000000000000000000" && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Price Oracle</span>
                        <CopyableAddress address={assetPair.priceOracle} />
                    </div>
                )}
            </div>
        </div>
    )
}

/**
 * Asset Input Component - Reusable component for selecting assets via strategy or manual input
 * Manages all internal state and returns the resolved address via onChange
 */
function AssetInput({
    strategies,
    isLoadingStrategies,
    chainId,
    onChange,
    disabled,
    label,
    showStrategyOption = true,
}: {
    strategies: Address[]
    isLoadingStrategies: boolean
    chainId: SupportedChainId | undefined
    onChange: (address: Address | undefined) => void
    disabled?: boolean
    label?: string
    showStrategyOption?: boolean
}) {
    // Internal state management
    const [mode, setMode] = useState<"strategy" | "manual">(showStrategyOption ? "strategy" : "manual")
    const [selectedStrategy, setSelectedStrategy] = useState("")
    const [manualInput, setManualInput] = useState("")
    
    // Determine effective mode (always manual if strategy option is hidden)
    const effectiveMode = showStrategyOption ? mode : "manual"
    
    // Get underlying token for selected strategy (only when in strategy mode)
    const { underlyingToken: strategyAsset } = useStrategyUnderlyingToken(
        effectiveMode === "strategy" && selectedStrategy ? (selectedStrategy as Address) : undefined,
        chainId
    )
    
    // Compute the resolved address based on mode
    const resolvedAddress = useMemo(() => {
        if (effectiveMode === "strategy") {
            return strategyAsset
        } else {
            return isAddress(manualInput) ? (manualInput as Address) : undefined
        }
    }, [effectiveMode, strategyAsset, manualInput])

    // Get token info for resolved address
    const assetInfo = useTokenInfo(resolvedAddress, chainId)
    
    // Notify parent when resolved address changes
    useEffect(() => {
        onChange(resolvedAddress)
    }, [resolvedAddress, onChange])
    
    // Handle mode change
    const handleModeChange = (newMode: "strategy" | "manual") => {
        setMode(newMode)
        // Clear the other mode's state when switching
        if (newMode === "strategy") {
            setManualInput("")
        } else {
            setSelectedStrategy("")
        }
    }

    return (
        <div className="space-y-2">
            <div className="flex items-center justify-between">
                <Label>{label || "Asset"}</Label>
                {showStrategyOption && (
                    <Tabs
                        value={mode}
                        onValueChange={(v) => handleModeChange(v as "strategy" | "manual")}
                        className="w-auto"
                    >
                        <TabsList className="h-8">
                            <TabsTrigger value="strategy" className="text-xs px-2" disabled={disabled}>
                                Strategy
                            </TabsTrigger>
                            <TabsTrigger value="manual" className="text-xs px-2" disabled={disabled}>
                                Manual
                            </TabsTrigger>
                        </TabsList>
                    </Tabs>
                )}
            </div>
            {effectiveMode === "strategy" ? (
                <>
                    {isLoadingStrategies ? (
                        <div className="flex items-center gap-2 text-sm text-muted-foreground">
                            <Loader2 className="size-4 animate-spin" />
                            Loading strategies...
                        </div>
                    ) : (
                        <Select
                            value={selectedStrategy}
                            onValueChange={setSelectedStrategy}
                            disabled={disabled}
                        >
                            <SelectTrigger className="font-mono">
                                <SelectValue placeholder="Select strategy asset..." />
                            </SelectTrigger>
                            <SelectContent>
                                {strategies.length === 0 ? (
                                    <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                                        No whitelisted strategies available.
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
                    )}
                    {resolvedAddress && (
                        <div className="flex items-center gap-2 text-xs text-muted-foreground">
                            <span>Underlying:</span>
                            <CopyableAddress address={resolvedAddress} />
                        </div>
                    )}
                </>
            ) : (
                <>
                    <Input
                        placeholder="0x..."
                        value={manualInput}
                        onChange={(e) => setManualInput(e.target.value)}
                        className="font-mono"
                        disabled={disabled}
                    />
                    {manualInput && !isAddress(manualInput) && (
                        <p className="text-xs text-destructive">Invalid address</p>
                    )}
                    {assetInfo.tokenSymbol && (
                        <p className="text-xs text-muted-foreground">
                            Token: {assetInfo.tokenName} ({assetInfo.tokenSymbol})
                        </p>
                    )}
                </>
            )}
        </div>
    )
}

/**
 * Read functionality section - Quote operations
 */
function ReadSection({
    contract,
    chainId,
    strategies,
    isLoadingStrategies,
    swapSlippage,
    isLoadingSlippage,
    refetchSlippage,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    strategies: Address[]
    isLoadingStrategies: boolean
    swapSlippage: number | undefined
    isLoadingSlippage: boolean
    refetchSlippage: () => void
}) {
    // State for asset selection
    const [assetA, setAssetA] = useState<Address | undefined>()
    const [assetB, setAssetB] = useState<Address | undefined>()
    const [amountInput, setAmountInput] = useState("")
    const [quoteType, setQuoteType] = useState<"getQuote" | "swapForInput" | "swapForOutput">(
        "getQuote"
    )

    // Get token info for both assets
    const assetAInfo = useTokenInfo(assetA, chainId)
    const assetBInfo = useTokenInfo(assetB, chainId)

    // Parse amount based on quote type
    // All quote types take Asset B amount (what you spend/output from wallet)
    const parsedAmount = useMemo(() => {
        if (!amountInput || amountInput.trim() === "") return undefined
        try {
            const decimals = assetBInfo.tokenDecimals || 18
            return parseUnits(amountInput, decimals)
        } catch {
            return undefined
        }
    }, [amountInput, assetBInfo.tokenDecimals])
    
    // Check if input is valid
    const isValidAmount = useMemo(() => {
        if (!amountInput || amountInput.trim() === "") return true // Empty is valid
        return parsedAmount !== undefined
    }, [amountInput, parsedAmount])

    // Get asset pair info
    const {
        data: assetPair,
        isLoading: isLoadingAssetPair,
        refetch: refetchAssetPair,
    } = useReadContract({
        address: contract.address,
        abi: iAssetPriceOracleAndSwapperAbi,
        functionName: "assetPair",
        args: assetA && assetB ? [assetA, assetB] : undefined,
        chainId,
        query: {
            enabled: !!assetA && !!assetB && !!chainId,
        },
    })

    // Get quote
    const {
        data: quoteResult,
        isLoading: isLoadingQuote,
        refetch: refetchQuote,
    } = useReadContract({
        address: contract.address,
        abi: iAssetPriceOracleAndSwapperAbi,
        functionName: "getQuote",
        args: parsedAmount && assetA && assetB ? [parsedAmount, assetA, assetB] : undefined,
        chainId,
        query: {
            enabled:
                quoteType === "getQuote" && !!parsedAmount && !!assetA && !!assetB && !!chainId,
        },
    })

    // Get swap for input quote
    const {
        data: swapForInputResult,
        isLoading: isLoadingSwapForInput,
        refetch: refetchSwapForInput,
    } = useReadContract({
        address: contract.address,
        abi: iAssetPriceOracleAndSwapperAbi,
        functionName: "swapForInputQuote",
        args: parsedAmount && assetA && assetB ? [parsedAmount, assetA, assetB] : undefined,
        chainId,
        query: {
            enabled:
                quoteType === "swapForInput" && !!parsedAmount && !!assetA && !!assetB && !!chainId,
        },
    })

    // Get swap for output quote
    const {
        data: swapForOutputResult,
        isLoading: isLoadingSwapForOutput,
        refetch: refetchSwapForOutput,
    } = useReadContract({
        address: contract.address,
        abi: iAssetPriceOracleAndSwapperAbi,
        functionName: "swapForOutputQuote",
        args: parsedAmount && assetA && assetB ? [parsedAmount, assetA, assetB] : undefined,
        chainId,
        query: {
            enabled:
                quoteType === "swapForOutput" &&
                !!parsedAmount &&
                !!assetA &&
                !!assetB &&
                !!chainId,
        },
    })

    console.log("parsedAmount", parsedAmount)
    console.log("input amount", amountInput)

    const handleRefresh = () => {
        refetchSlippage()
        if (assetA && assetB) {
            refetchAssetPair()
            if (parsedAmount) {
                if (quoteType === "getQuote") refetchQuote()
                if (quoteType === "swapForInput") refetchSwapForInput()
                if (quoteType === "swapForOutput") refetchSwapForOutput()
            }
        }
    }

    const isLoading = isLoadingQuote || isLoadingSwapForInput || isLoadingSwapForOutput

    // Type-safe extraction of quote results
    const quoteData = quoteResult as [bigint, boolean] | undefined
    const quote = quoteData?.[0]
    const verified = quoteData?.[1]

    return (
        <div className="space-y-6">
            {/* Swap Slippage Display */}
            <div className="flex items-center justify-between rounded-lg bg-muted/50 p-4">
                <div className="flex items-center gap-3">
                    <ArrowRightLeft className="size-5 text-muted-foreground" />
                    <div>
                        <p className="text-sm font-medium">Current Swap Slippage</p>
                        <p className="text-xs text-muted-foreground">
                            Maximum slippage tolerance for swaps
                        </p>
                    </div>
                </div>
                <div className="flex items-center gap-2">
                    {isLoadingSlippage ? (
                        <Loader2 className="size-4 animate-spin" />
                    ) : (
                        <Badge variant="default" className="text-lg px-3 py-1">
                            {swapSlippage !== undefined
                                ? `${(swapSlippage / 100).toFixed(2)}%`
                                : "N/A"}
                        </Badge>
                    )}
                    <Button variant="ghost" size="sm" onClick={refetchSlippage}>
                        <RefreshCw className="size-4" />
                    </Button>
                </div>
            </div>

            {/* Asset Selection */}
            <div className="space-y-4">
                <div className="rounded-lg bg-muted/50 p-3">
                    <h4 className="text-sm font-medium">Query Price Quotes</h4>
                    <p className="text-xs text-muted-foreground mt-1">
                        Select assets and get price quotes for swaps
                    </p>
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                    {/* Asset A - from strategy or manual input */}
                    <AssetInput
                        strategies={strategies}
                        isLoadingStrategies={isLoadingStrategies}
                        chainId={chainId}
                        onChange={setAssetA}
                        label="Asset A (Output/Base)"
                    />

                    {/* Asset B - manual input only */}
                    <AssetInput
                        strategies={strategies}
                        isLoadingStrategies={isLoadingStrategies}
                        chainId={chainId}
                        onChange={setAssetB}
                        label="Asset B (Input/Swap)"
                        showStrategyOption={true}
                    />
                </div>

                {/* Quote Type Selection */}
                <div className="space-y-2">
                    <Label>Quote Type</Label>
                    <Tabs
                        value={quoteType}
                        onValueChange={(v) =>
                            setQuoteType(v as "getQuote" | "swapForInput" | "swapForOutput")
                        }
                    >
                        <TabsList className="grid w-full grid-cols-3">
                            <TabsTrigger value="getQuote">
                                <Calculator className="mr-2 size-4" />
                                Get Quote
                            </TabsTrigger>
                            <TabsTrigger value="swapForInput">Swap Input Quote</TabsTrigger>
                            <TabsTrigger value="swapForOutput">Swap Output Quote</TabsTrigger>
                        </TabsList>
                        <TabsContent value="getQuote" className="mt-4">
                            <p className="text-xs text-muted-foreground">
                                Get the equivalent amount of Asset A for a given amount of Asset B
                            </p>
                        </TabsContent>
                        <TabsContent value="swapForInput" className="mt-4">
                            <p className="text-xs text-muted-foreground">
                                Get the minimum amount of Asset A tokens that can be received for an
                                exact input of Asset B
                            </p>
                        </TabsContent>
                        <TabsContent value="swapForOutput" className="mt-4">
                            <p className="text-xs text-muted-foreground">
                                Enter the amount of Asset B you want to spend (output from wallet)
                                to see the minimum Asset A you will receive
                            </p>
                        </TabsContent>
                    </Tabs>
                </div>

                {/* Amount Input */}
                <div className="space-y-2">
                    <Label>
                        {quoteType === "swapForOutput"
                            ? `Amount Out (${assetBInfo.tokenSymbol || "Asset B"})`
                            : `Amount In (${assetBInfo.tokenSymbol || "Asset B"})`}
                    </Label>
                    <div className="flex gap-2">
                        <Input
                            type="text"
                            inputMode="decimal"
                            placeholder="0.0"
                            value={amountInput}
                            onChange={(e) => {
                                // Allow decimal input (e.g., "1.5", "0.1")
                                const value = e.target.value
                                // Allow empty, numbers, and single decimal point
                                if (value === "" || /^\d*\.?\d*$/.test(value)) {
                                    setAmountInput(value)
                                }
                            }}
                            className="font-mono"
                            aria-invalid={!isValidAmount}
                        />
                        {!isValidAmount && amountInput && (
                            <p className="text-xs text-destructive">
                                Invalid amount. Please enter a valid number.
                            </p>
                        )}
                        {isValidAmount && amountInput && (
                            <p className="text-xs text-muted-foreground">
                                Enter amount in {assetBInfo.tokenSymbol || "Asset B"} units
                                {` (${assetBInfo.tokenDecimals || 18} decimals)`}
                            </p>
                        )}
                        <Button
                            variant="outline"
                            onClick={handleRefresh}
                            disabled={!assetA || !assetB || !parsedAmount || isLoading}
                        >
                            {isLoading ? (
                                <Loader2 className="mr-2 size-4 animate-spin" />
                            ) : (
                                <RefreshCw className="mr-2 size-4" />
                            )}
                            Get Quote
                        </Button>
                    </div>
                </div>

                {/* Asset Pair Info */}
                {isLoadingAssetPair && assetA && assetB && (
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Loader2 className="size-4 animate-spin" />
                        Loading asset pair configuration...
                    </div>
                )}

                {assetPair &&
                    assetPair.swapEngine !== "0x0000000000000000000000000000000000000000" && (
                        <AssetPairInfo assetPair={assetPair} />
                    )}

                {assetPair &&
                    assetPair.swapEngine === "0x0000000000000000000000000000000000000000" &&
                    assetA &&
                    assetB && (
                        <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4 text-sm text-destructive">
                            Asset pair not registered. Register this pair in the Write section to
                            enable swaps.
                        </div>
                    )}

                {/* Quote Results */}
                {(quote !== undefined ||
                    swapForInputResult !== undefined ||
                    swapForOutputResult !== undefined) && (
                    <QuoteResults
                        quote={quoteType === "getQuote" ? quote : undefined}
                        verified={quoteType === "getQuote" ? verified : undefined}
                        minAmountOut={
                            quoteType === "swapForInput"
                                ? (swapForInputResult as bigint)
                                : undefined
                        }
                        maxAmountIn={
                            quoteType === "swapForOutput"
                                ? (swapForOutputResult as bigint)
                                : undefined
                        }
                        assetASymbol={assetAInfo.tokenSymbol}
                        assetADecimals={assetAInfo.tokenDecimals}
                    />
                )}
            </div>
        </div>
    )
}

/**
 * Write functionality section - Register and Set Slippage
 */
function WriteSection({
    contract,
    chainId,
    strategies,
    isLoadingStrategies,
    swapSlippage,
    refetchSlippage,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    strategies: Address[]
    isLoadingStrategies: boolean
    swapSlippage: number | undefined
    refetchSlippage: () => void
}) {
    // Slippage state - slider value in basis points (1 = 0.01%)
    const [slippageValue, setSlippageValue] = useState(swapSlippage ?? 100) // Default 1%
    const [slippageInput, setSlippageInput] = useState(
        swapSlippage !== undefined ? (swapSlippage / 100).toFixed(2) : "1.00"
    )

    // Register form state
    const [assetA, setAssetA] = useState<Address | undefined>()
    const [assetB, setAssetB] = useState<Address | undefined>()
    const [swapEngine, setSwapEngine] = useState("")
    const [poolInfo, setPoolInfo] = useState("")
    const [poolInfoMode, setPoolInfoMode] = useState<"custom" | "uniswapV3">("custom")
    const [uniswapV3PoolInfo, setUniswapV3PoolInfo] = useState("")
    const [priceStrategy, setPriceStrategy] = useState("1") // Default: Swapper Only
    const [swapperAccuracy, setSwapperAccuracy] = useState("100") // Default: 1%
    const [priceOracle, setPriceOracle] = useState("")

    // Compute pool info based on mode
    const computedPoolInfo = useMemo(() => {
        if (poolInfoMode === "custom") {
            return poolInfo
        }
        return uniswapV3PoolInfo
    }, [poolInfoMode, poolInfo, uniswapV3PoolInfo])

    // Validate inputs
    const isValidSwapEngine = isAddress(swapEngine)
    const isValidPoolInfo = computedPoolInfo.startsWith("0x") || computedPoolInfo === ""
    const isValidPriceOracle = priceOracle === "" || isAddress(priceOracle)

    // Update slippage when contract value changes
    useEffect(() => {
        if (swapSlippage !== undefined) {
            // eslint-disable-next-line react-hooks/set-state-in-effect
            setSlippageValue(swapSlippage)
            setSlippageInput((swapSlippage / 100).toFixed(2))
        }
    }, [swapSlippage])

    // Write contract hooks for setSwapSlippage
    const {
        writeContract: writeSlippage,
        isPending: isSlippagePending,
        data: slippageHash,
    } = useWriteContract()
    const { isLoading: isSlippageConfirming, isSuccess: isSlippageSuccess, isError: isSlippageReceiptError, error: slippageReceiptError } =
        useWaitForTransactionReceipt({ hash: slippageHash })

    // Write contract hooks for register
    const {
        writeContract: writeRegister,
        isPending: isRegisterPending,
        data: registerHash,
    } = useWriteContract()
    const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess, isError: isRegisterReceiptError, error: registerReceiptError } =
        useWaitForTransactionReceipt({ hash: registerHash })

    // Track slippage success for refetch
    const prevSlippageSuccessRef = useRef(false)
    const hasShownSlippageReceiptError = useRef<string>("")
    const hasShownRegisterReceiptError = useRef<string>("")

    useEffect(() => {
        if (isSlippageSuccess && !prevSlippageSuccessRef.current) {
            refetchSlippage()
            toast.success("Swap slippage updated successfully!")
        }
        prevSlippageSuccessRef.current = isSlippageSuccess
    }, [isSlippageSuccess, refetchSlippage])

    // Handle slippage transaction receipt errors
    useEffect(() => {
        if (isSlippageReceiptError && slippageReceiptError && slippageHash && hasShownSlippageReceiptError.current !== slippageHash) {
            hasShownSlippageReceiptError.current = slippageHash
            const decodedError = decodeContractError(slippageReceiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
        }
    }, [isSlippageReceiptError, slippageReceiptError, slippageHash])

    // Handle register transaction receipt errors
    useEffect(() => {
        if (isRegisterReceiptError && registerReceiptError && registerHash && hasShownRegisterReceiptError.current !== registerHash) {
            hasShownRegisterReceiptError.current = registerHash
            const decodedError = decodeContractError(registerReceiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
        }
    }, [isRegisterReceiptError, registerReceiptError, registerHash])

    // Handle slider change
    const handleSliderChange = useCallback((values: number[]) => {
        setSlippageValue(values[0])
        setSlippageInput((values[0] / 100).toFixed(2))
    }, [])

    // Handle input change
    const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
        const inputValue = e.target.value
        setSlippageInput(inputValue)
        const parsed = parseFloat(inputValue)
        if (!isNaN(parsed) && parsed >= 0 && parsed <= 20) {
            setSlippageValue(Math.round(parsed * 100))
        }
    }, [])

    // Handle set slippage
    const handleSetSlippage = () => {
        writeSlippage(
            {
                address: contract.address,
                abi: iAssetPriceOracleAndSwapperAbi,
                functionName: "setSwapSlippage",
                args: [slippageValue],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    // Handle register
    const handleRegister = () => {
        if (!assetA || !assetB || !isValidSwapEngine) {
            toast.error("Please fill in all required fields")
            return
        }

        const assetPair = {
            assetA,
            assetB,
            swapEngine: swapEngine as Address,
            poolInfo: (computedPoolInfo || "0x") as `0x${string}`,
            priceStrategy: Number(priceStrategy),
            swapperAccuracy: Number(swapperAccuracy),
            priceOracle: (priceOracle || "0x0000000000000000000000000000000000000000") as Address,
        }

        console.log("assetPair", assetPair)

        writeRegister(
            {
                address: contract.address,
                abi: iAssetPriceOracleAndSwapperAbi,
                functionName: "register",
                args: [assetPair],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    const isRegisterValid = useMemo(() => {
        return (
            assetA &&
            assetB &&
            isValidSwapEngine &&
            isValidPoolInfo &&
            isValidPriceOracle &&
            (priceStrategy === "1" || // Swapper Only doesn't need oracle
                (priceOracle && isAddress(priceOracle))) // Other strategies need oracle
        )
    }, [
        assetA,
        assetB,
        isValidSwapEngine,
        isValidPoolInfo,
        isValidPriceOracle,
        priceStrategy,
        priceOracle,
    ])

    return (
        <div className="space-y-6">
            {/* Set Swap Slippage Section */}
            <div className="space-y-4">
                <div className="rounded-lg bg-muted/50 p-3">
                    <div className="flex items-center gap-2">
                        <Settings className="size-4" />
                        <h4 className="text-sm font-medium">Set Swap Slippage</h4>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                        Configure the maximum slippage tolerance for swaps (0.01% - 20%)
                    </p>
                </div>

                <div className="space-y-4">
                    <div className="space-y-2">
                        <div className="flex items-center justify-between">
                            <Label>Slippage Tolerance</Label>
                        </div>
                        <Slider
                            value={[slippageValue]}
                            onValueChange={handleSliderChange}
                            min={1}
                            max={2000}
                            step={1}
                        />
                        <div className="flex items-center justify-between text-xs text-muted-foreground">
                            <span>0.01%</span>
                            <span>20%</span>
                        </div>
                    </div>

                    <div className="flex items-center justify-center gap-2">
                        <div className="flex-1 space-y-2">
                            <Input
                                id="slippage-input"
                                type="number"
                                step="0.01"
                                min="0.01"
                                max="20"
                                value={slippageInput}
                                onChange={handleInputChange}
                                className="font-mono"
                                disabled={isSlippagePending || isSlippageConfirming}
                            />
                        </div>
                        <div className="flex items-end">
                            <Button
                                onClick={handleSetSlippage}
                                disabled={
                                    isSlippagePending ||
                                    isSlippageConfirming ||
                                    slippageValue === swapSlippage
                                }
                                size={"lg"}
                            >
                                {isSlippagePending || isSlippageConfirming ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <CheckCircle2 className="mr-2 size-4" />
                                )}
                                {isSlippagePending
                                    ? "Confirm..."
                                    : isSlippageConfirming
                                      ? "Setting..."
                                      : "Set Slippage"}
                            </Button>
                        </div>
                    </div>

                    {isSlippageSuccess && (
                        <p className="flex items-center gap-2 text-sm text-green-600">
                            <CheckCircle2 className="size-4" />
                            Slippage updated successfully!
                        </p>
                    )}
                </div>
            </div>

            <Separator />

            {/* Register Asset Pair Section */}
            <div className="space-y-4">
                <div className="rounded-lg bg-muted/50 p-3">
                    <div className="flex items-center gap-2">
                        <Plus className="size-4" />
                        <h4 className="text-sm font-medium">Register Asset Pair</h4>
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                        Register a new asset pair for price quotes and swapping
                    </p>
                </div>

                {/* Asset Selection */}
                <div className="grid gap-4 md:grid-cols-2">
                    {/* Asset A - from strategy or manual input */}
                    <AssetInput
                        strategies={strategies}
                        isLoadingStrategies={isLoadingStrategies}
                        chainId={chainId}
                        onChange={setAssetA}
                        label="Asset A (Output/Base)"
                        disabled={isRegisterPending || isRegisterConfirming}
                    />

                    {/* Asset B - manual input only */}
                    <AssetInput
                        strategies={strategies}
                        isLoadingStrategies={isLoadingStrategies}
                        chainId={chainId}
                        onChange={setAssetB}
                        label="Asset B (Input/Swap)"
                        showStrategyOption={false}
                        disabled={isRegisterPending || isRegisterConfirming}
                    />
                </div>

                {/* Swap Engine */}
                <div className="space-y-2">
                    <Label>Swap Engine Address</Label>
                    <Input
                        placeholder="0x..."
                        value={swapEngine}
                        onChange={(e) => setSwapEngine(e.target.value)}
                        className="font-mono"
                        disabled={isRegisterPending || isRegisterConfirming}
                    />
                    {swapEngine && !isValidSwapEngine && (
                        <p className="text-xs text-destructive">Invalid address</p>
                    )}
                    <p className="text-xs text-muted-foreground">
                        The swap engine contract that handles token swaps (e.g.,
                        UniswapV3SwapperEngine)
                    </p>
                </div>

                {/* Pool Info */}
                <div className="space-y-3">
                    <div className="flex items-center justify-between">
                        <Label>Pool Info</Label>
                        <Select
                            value={poolInfoMode}
                            onValueChange={(v) => setPoolInfoMode(v as "custom" | "uniswapV3")}
                            disabled={isRegisterPending || isRegisterConfirming}
                        >
                            <SelectTrigger className="w-[200px] h-8">
                                <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="custom">Custom (bytes)</SelectItem>
                                <SelectItem value="uniswapV3">Uniswap V3 Path</SelectItem>
                            </SelectContent>
                        </Select>
                    </div>

                    {poolInfoMode === "custom" ? (
                        <div className="space-y-2">
                            <Input
                                placeholder="0x... (optional)"
                                value={poolInfo}
                                onChange={(e) => setPoolInfo(e.target.value)}
                                className="font-mono"
                                disabled={isRegisterPending || isRegisterConfirming}
                            />
                            {poolInfo && !isValidPoolInfo && (
                                <p className="text-xs text-destructive">Must start with 0x</p>
                            )}
                            <p className="text-xs text-muted-foreground">
                                Raw pool information bytes for the swap engine
                            </p>
                        </div>
                    ) : (
                        <UniswapV3PoolInput
                            value={uniswapV3PoolInfo}
                            onChange={setUniswapV3PoolInfo}
                            disabled={isRegisterPending || isRegisterConfirming}
                        />
                    )}
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                    {/* Price Strategy */}
                    <div className="space-y-2">
                        <Label>Price Strategy</Label>
                        <Select
                            value={priceStrategy}
                            onValueChange={setPriceStrategy}
                            disabled={isRegisterPending || isRegisterConfirming}
                        >
                            <SelectTrigger>
                                <SelectValue placeholder="Select strategy..." />
                            </SelectTrigger>
                            <SelectContent>
                                {PRICE_STRATEGY_OPTIONS.map((option) => (
                                    <SelectItem key={option.value} value={option.value}>
                                        <div className="flex flex-col gap-0.5 items-start">
                                            <div className="font-medium">{option.label}</div>
                                            <div className="text-xs text-muted-foreground">
                                                {option.description}
                                            </div>
                                        </div>
                                    </SelectItem>
                                ))}
                            </SelectContent>
                        </Select>
                    </div>

                    {/* Swapper Accuracy */}
                    <div className="space-y-2">
                        <Label>Swapper Accuracy (basis points)</Label>
                        <Input
                            type="number"
                            placeholder="100"
                            value={swapperAccuracy}
                            onChange={(e) => setSwapperAccuracy(e.target.value)}
                            className="font-mono"
                            disabled={isRegisterPending || isRegisterConfirming}
                        />
                        <p className="text-xs text-muted-foreground">
                            {Number(swapperAccuracy) / 100}% accuracy tolerance
                        </p>
                    </div>
                </div>

                {/* Price Oracle - required for non-SwapperOnly strategies */}
                <div className="space-y-2">
                    <Label>
                        Price Oracle Address
                        {priceStrategy !== "1" && <span className="text-destructive ml-1">*</span>}
                    </Label>
                    <Input
                        placeholder="0x... (required for oracle-based strategies)"
                        value={priceOracle}
                        onChange={(e) => setPriceOracle(e.target.value)}
                        className="font-mono"
                        disabled={isRegisterPending || isRegisterConfirming}
                    />
                    {priceOracle && !isValidPriceOracle && (
                        <p className="text-xs text-destructive">Invalid address</p>
                    )}
                    {priceStrategy !== "1" && !priceOracle && (
                        <p className="text-xs text-amber-600">
                            Price oracle is required for{" "}
                            {PRICE_STRATEGY_OPTIONS[Number(priceStrategy)]?.label} strategy
                        </p>
                    )}
                </div>

                <Button
                    onClick={handleRegister}
                    disabled={!isRegisterValid || isRegisterPending || isRegisterConfirming}
                    className="w-full"
                >
                    {isRegisterPending || isRegisterConfirming ? (
                        <Loader2 className="mr-2 size-4 animate-spin" />
                    ) : (
                        <Plus className="mr-2 size-4" />
                    )}
                    {isRegisterPending
                        ? "Confirm in wallet..."
                        : isRegisterConfirming
                          ? "Registering..."
                          : "Register Asset Pair"}
                </Button>

                {isRegisterSuccess && (
                    <p className="flex items-center gap-2 text-sm text-green-600">
                        <CheckCircle2 className="size-4" />
                        Asset pair registered successfully!
                    </p>
                )}
            </div>
        </div>
    )
}

/**
 * Main AssetPriceOracleAndSwapperInteraction component
 */
export function AssetPriceOracleAndSwapperInteraction({
    contract,
    chainId,
    strategies,
    isLoadingStrategies,
}: AssetPriceOracleAndSwapperInteractionProps) {
    // Get swap slippage
    const {
        data: swapSlippage,
        isLoading: isLoadingSlippage,
        refetch: refetchSlippage,
    } = useReadContract({
        address: contract.address,
        abi: iAssetPriceOracleAndSwapperAbi,
        functionName: "swapSlippage",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center justify-between">
                    <div>
                        <CardTitle className="flex items-center gap-2">
                            <Coins className="size-5" />
                            Asset Price Oracle & Swapper
                        </CardTitle>
                        <CardDescription>
                            Query price quotes and manage asset pair configurations for swapping
                        </CardDescription>
                    </div>
                </div>
            </CardHeader>
            <CardContent>
                <Tabs defaultValue="read" className="space-y-4">
                    <TabsList className="grid w-full grid-cols-2">
                        <TabsTrigger value="read">
                            <Calculator className="mr-2 size-4" />
                            Quotes
                        </TabsTrigger>
                        <TabsTrigger value="write">
                            <Settings className="mr-2 size-4" />
                            Configure
                        </TabsTrigger>
                    </TabsList>

                    <TabsContent value="read">
                        <ReadSection
                            contract={contract}
                            chainId={chainId}
                            strategies={strategies}
                            isLoadingStrategies={isLoadingStrategies}
                            swapSlippage={swapSlippage as number | undefined}
                            isLoadingSlippage={isLoadingSlippage}
                            refetchSlippage={refetchSlippage}
                        />
                    </TabsContent>

                    <TabsContent value="write">
                        <WriteSection
                            contract={contract}
                            chainId={chainId}
                            strategies={strategies}
                            isLoadingStrategies={isLoadingStrategies}
                            swapSlippage={swapSlippage as number | undefined}
                            refetchSlippage={refetchSlippage}
                        />
                    </TabsContent>
                </Tabs>
            </CardContent>
        </Card>
    )
}
