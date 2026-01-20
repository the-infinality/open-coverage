import { useState, useMemo, useEffect, useRef, useCallback } from "react"
import { type Address, isAddress, parseUnits, formatUnits } from "viem"
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

type SupportedChainId = (typeof supportedChains)[number]["id"]

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
            <span className="flex items-center gap-2">
                <Loader2 className="size-3 animate-spin" />
                Loading...
            </span>
        )
    }

    return (
        <span className="flex flex-col gap-0.5">
            <span className="font-medium">
                {tokenName && tokenSymbol
                    ? `${tokenName} (${tokenSymbol})`
                    : underlyingToken
                      ? `${underlyingToken.slice(0, 10)}...${underlyingToken.slice(-8)}`
                      : "Unknown Asset"}
            </span>
            <span className="text-xs text-muted-foreground">
                Strategy: {strategyAddress.slice(0, 10)}...{strategyAddress.slice(-8)}
            </span>
        </span>
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
    assetBSymbol,
    assetADecimals,
    assetBDecimals,
}: {
    quote?: bigint
    verified?: boolean
    minAmountOut?: bigint
    maxAmountIn?: bigint
    assetASymbol?: string
    assetBSymbol?: string
    assetADecimals?: number
    assetBDecimals?: number
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
                        <span className="text-muted-foreground">Min Amount Out (swap input)</span>
                        <span className="font-mono">
                            {formatUnits(minAmountOut, assetADecimals || 18)}{" "}
                            {assetASymbol || "tokens"}
                        </span>
                    </div>
                )}
                {maxAmountIn !== undefined && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Max Amount In (swap output)</span>
                        <span className="font-mono">
                            {formatUnits(maxAmountIn, assetBDecimals || 18)}{" "}
                            {assetBSymbol || "tokens"}
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
    const [selectedStrategy, setSelectedStrategy] = useState("")
    const [assetBInput, setAssetBInput] = useState("")
    const [amountInput, setAmountInput] = useState("")
    const [quoteType, setQuoteType] = useState<"getQuote" | "swapForInput" | "swapForOutput">(
        "getQuote"
    )

    // Get underlying token for selected strategy (this will be Asset A)
    const { underlyingToken: assetA } = useStrategyUnderlyingToken(
        selectedStrategy ? (selectedStrategy as Address) : undefined,
        chainId
    )

    // Validate asset B
    const assetB = isAddress(assetBInput) ? (assetBInput as Address) : undefined

    // Get token info for both assets
    const assetAInfo = useTokenInfo(assetA, chainId)
    const assetBInfo = useTokenInfo(assetB, chainId)

    // Parse amount based on quote type (input vs output)
    const parsedAmount = useMemo(() => {
        if (!amountInput) return undefined
        try {
            const decimals =
                quoteType === "swapForOutput"
                    ? assetAInfo.tokenDecimals || 18
                    : assetBInfo.tokenDecimals || 18
            return parseUnits(amountInput, decimals)
        } catch {
            return undefined
        }
    }, [amountInput, quoteType, assetAInfo.tokenDecimals, assetBInfo.tokenDecimals])

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
                    {/* Asset A - from strategy */}
                    <div className="space-y-2">
                        <Label>Asset A (Output/Base) - From Strategy</Label>
                        {isLoadingStrategies ? (
                            <div className="flex items-center gap-2 text-sm text-muted-foreground">
                                <Loader2 className="size-4 animate-spin" />
                                Loading strategies...
                            </div>
                        ) : (
                            <Select value={selectedStrategy} onValueChange={setSelectedStrategy}>
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
                        {assetA && (
                            <div className="flex items-center gap-2 text-xs text-muted-foreground">
                                <span>Underlying:</span>
                                <CopyableAddress address={assetA} />
                            </div>
                        )}
                    </div>

                    {/* Asset B - manual input */}
                    <div className="space-y-2">
                        <Label>Asset B (Input/Swap)</Label>
                        <Input
                            placeholder="0x..."
                            value={assetBInput}
                            onChange={(e) => setAssetBInput(e.target.value)}
                            className="font-mono"
                        />
                        {assetBInput && !isAddress(assetBInput) && (
                            <p className="text-xs text-destructive">Invalid address</p>
                        )}
                        {assetBInfo.tokenSymbol && (
                            <p className="text-xs text-muted-foreground">
                                Token: {assetBInfo.tokenName} ({assetBInfo.tokenSymbol})
                            </p>
                        )}
                    </div>
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
                                Get the maximum amount of Asset B tokens needed to receive an exact
                                output of Asset A
                            </p>
                        </TabsContent>
                    </Tabs>
                </div>

                {/* Amount Input */}
                <div className="space-y-2">
                    <Label>
                        {quoteType === "swapForOutput"
                            ? `Amount Out (${assetAInfo.tokenSymbol || "Asset A"})`
                            : `Amount In (${assetBInfo.tokenSymbol || "Asset B"})`}
                    </Label>
                    <div className="flex gap-2">
                        <Input
                            type="text"
                            placeholder="0.0"
                            value={amountInput}
                            onChange={(e) => setAmountInput(e.target.value)}
                            className="font-mono"
                        />
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
                        assetBSymbol={assetBInfo.tokenSymbol}
                        assetADecimals={assetAInfo.tokenDecimals}
                        assetBDecimals={assetBInfo.tokenDecimals}
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
    const [selectedStrategyA, setSelectedStrategyA] = useState("")
    const [assetBInput, setAssetBInput] = useState("")
    const [swapEngine, setSwapEngine] = useState("")
    const [poolInfo, setPoolInfo] = useState("")
    const [priceStrategy, setPriceStrategy] = useState("1") // Default: Swapper Only
    const [swapperAccuracy, setSwapperAccuracy] = useState("100") // Default: 1%
    const [priceOracle, setPriceOracle] = useState("")

    // Get underlying token for selected strategy
    const { underlyingToken: assetA } = useStrategyUnderlyingToken(
        selectedStrategyA ? (selectedStrategyA as Address) : undefined,
        chainId
    )

    // Validate inputs
    const assetB = isAddress(assetBInput) ? (assetBInput as Address) : undefined
    const isValidSwapEngine = isAddress(swapEngine)
    const isValidPoolInfo = poolInfo.startsWith("0x") || poolInfo === ""
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
    const { isLoading: isSlippageConfirming, isSuccess: isSlippageSuccess } =
        useWaitForTransactionReceipt({ hash: slippageHash })

    // Write contract hooks for register
    const {
        writeContract: writeRegister,
        isPending: isRegisterPending,
        data: registerHash,
    } = useWriteContract()
    const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess } =
        useWaitForTransactionReceipt({ hash: registerHash })

    // Track slippage success for refetch
    const prevSlippageSuccessRef = useRef(false)
    useEffect(() => {
        if (isSlippageSuccess && !prevSlippageSuccessRef.current) {
            refetchSlippage()
            toast.success("Swap slippage updated successfully!")
        }
        prevSlippageSuccessRef.current = isSlippageSuccess
    }, [isSlippageSuccess, refetchSlippage])

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
                    toast.error(error.message.slice(0, 100))
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
            poolInfo: (poolInfo || "0x") as `0x${string}`,
            priceStrategy: Number(priceStrategy),
            swapperAccuracy: Number(swapperAccuracy),
            priceOracle: (priceOracle || "0x0000000000000000000000000000000000000000") as Address,
        }

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
                    toast.error(error.message.slice(0, 100))
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
                    {/* Asset A - from strategy */}
                    <div className="space-y-2">
                        <Label>Asset A (Output/Base) - From Strategy</Label>
                        {isLoadingStrategies ? (
                            <div className="flex items-center gap-2 text-sm text-muted-foreground">
                                <Loader2 className="size-4 animate-spin" />
                                Loading strategies...
                            </div>
                        ) : (
                            <Select
                                value={selectedStrategyA}
                                onValueChange={setSelectedStrategyA}
                                disabled={isRegisterPending || isRegisterConfirming}
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
                        {assetA && (
                            <div className="flex items-center gap-2 text-xs text-muted-foreground">
                                <span>Underlying:</span>
                                <CopyableAddress address={assetA} />
                            </div>
                        )}
                    </div>

                    {/* Asset B - manual input */}
                    <div className="space-y-2">
                        <Label>Asset B (Input/Swap)</Label>
                        <Input
                            placeholder="0x..."
                            value={assetBInput}
                            onChange={(e) => setAssetBInput(e.target.value)}
                            className="font-mono"
                            disabled={isRegisterPending || isRegisterConfirming}
                        />
                        {assetBInput && !isAddress(assetBInput) && (
                            <p className="text-xs text-destructive">Invalid address</p>
                        )}
                    </div>
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
                <div className="space-y-2">
                    <Label>Pool Info (bytes)</Label>
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
                        Pool-specific information for the swap engine (e.g., encoded pool fee for
                        Uniswap)
                    </p>
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
                            Read (Quotes)
                        </TabsTrigger>
                        <TabsTrigger value="write">
                            <Settings className="mr-2 size-4" />
                            Write (Configure)
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
