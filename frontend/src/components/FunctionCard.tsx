import { useMemo, useState } from "react"
import { toast } from "sonner"
import { useAccount, useWalletClient } from "wagmi"
import { type AbiFunction } from "viem"
import { getPublicClientForChain } from "@/lib/wagmi"
import {
    getAbisForContractType,
    getAbisForCoverageProviderWithInterfaces,
    type NamedAbi,
} from "@/lib/abi"
import { useCheckCoverageProviderSupport } from "@/hooks/use-interface-support"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { cn, truncateAddress } from "@/lib/utils"
import { ChevronDown, Play, Eye, AlertCircle, CheckCircle2, RefreshCw, Loader2 } from "lucide-react"
import type { CoverageContract } from "@/types/contracts"

interface FunctionCallResult {
    success: boolean
    result?: unknown
    error?: string
}

// Type for ABI parameter with components (tuples)
interface AbiParameterWithComponents {
    name?: string
    type: string
    components?: AbiParameterWithComponents[]
}

/**
 * Renders inputs for a single ABI parameter, handling tuples recursively
 */
function ParameterInput({
    param,
    path,
    args,
    setArgs,
    depth = 0,
}: {
    param: AbiParameterWithComponents
    path: string
    args: Record<string, string>
    setArgs: (args: Record<string, string>) => void
    depth?: number
}) {
    const isTuple = param.type === "tuple" || param.type.startsWith("tuple")
    const isArray = param.type.endsWith("[]")
    const displayName = param.name || path.split(".").pop() || "value"

    // For tuple types with components, render nested inputs
    if (isTuple && param.components && param.components.length > 0 && !isArray) {
        return (
            <div
                className={cn(
                    "space-y-2 p-2.5 border border-border rounded-md",
                    depth > 0 && "ml-4"
                )}
            >
                <Label className="text-xs font-medium">
                    {displayName} <span className="text-muted-foreground">({param.type})</span>
                </Label>
                <div className="space-y-3">
                    {param.components.map((component, idx) => (
                        <ParameterInput
                            key={idx}
                            param={component}
                            path={`${path}.${component.name || idx}`}
                            args={args}
                            setArgs={setArgs}
                            depth={depth + 1}
                        />
                    ))}
                </div>
            </div>
        )
    }

    // For simple types (or tuple arrays which need JSON input)
    return (
        <div className={cn(depth > 0 && "")}>
            <Label className="text-xs">
                {displayName} <span className="text-muted-foreground">({param.type})</span>
            </Label>
            <Input
                placeholder={param.type}
                className="mt-1 font-mono text-sm"
                value={args[path] || ""}
                onChange={(e) =>
                    setArgs({
                        ...args,
                        [path]: e.target.value,
                    })
                }
            />
        </div>
    )
}

/**
 * Parses a flat args object with dot-notation paths into nested values for tuple parameters
 */
function parseArgsForParam(
    param: AbiParameterWithComponents,
    args: Record<string, string>,
    basePath: string
): unknown {
    const isTuple = param.type === "tuple" || param.type.startsWith("tuple")
    const isArray = param.type.endsWith("[]")

    // For tuple types with components (not arrays), build nested object
    if (isTuple && param.components && param.components.length > 0 && !isArray) {
        const result: Record<string, unknown> = {}
        for (const component of param.components) {
            const componentPath = `${basePath}.${component.name || param.components.indexOf(component)}`
            result[component.name || String(param.components.indexOf(component))] =
                parseArgsForParam(component, args, componentPath)
        }
        return result
    }

    // For simple types, parse the value
    const value = args[basePath] || ""

    if (param.type === "uint256" || param.type === "int256" || param.type.match(/^u?int\d+$/)) {
        return BigInt(value || "0")
    }
    if (param.type === "bool") {
        return value.toLowerCase() === "true"
    }
    if (param.type.endsWith("[]") || param.type === "tuple[]") {
        try {
            return JSON.parse(value)
        } catch {
            return []
        }
    }
    if (param.type === "bytes" || param.type.match(/^bytes\d+$/)) {
        return value as `0x${string}`
    }
    return value
}

interface FunctionMethodProps {
    fn: AbiFunction
    contractAddress: `0x${string}`
    chainId: number
}

function FunctionMethod({ fn, contractAddress, chainId }: FunctionMethodProps) {
    const [isOpen, setIsOpen] = useState(false)
    const [result, setResult] = useState<FunctionCallResult | null>(null)
    const [isLoading, setIsLoading] = useState(false)
    const [args, setArgs] = useState<Record<string, string>>({})
    const [hasAutoQueried, setHasAutoQueried] = useState(false)

    // Use public RPC client for read operations (not wallet RPC)
    // getPublicClientForChain explicitly uses the public RPC transport
    // Use the contract's chainId, not the wallet's chain
    const publicClient = getPublicClientForChain(chainId)
    const { data: walletClient } = useWalletClient()
    const { address } = useAccount()

    const isReadFunction = fn.stateMutability === "view" || fn.stateMutability === "pure"

    // Check if this is a no-argument read function (can auto-query)
    const canAutoQuery = isReadFunction && fn.inputs.length === 0

    const handleCall = async () => {
        setIsLoading(true)
        setResult(null)

        try {
            // Parse arguments (handles tuples recursively)
            const parsedArgs = fn.inputs.map((input, index) => {
                const basePath = input.name || `arg${index}`
                return parseArgsForParam(input as AbiParameterWithComponents, args, basePath)
            })

            if (isReadFunction) {
                // Read call
                const data = await publicClient?.readContract({
                    address: contractAddress,
                    abi: [fn],
                    functionName: fn.name,
                    args: parsedArgs,
                })
                setResult({ success: true, result: data })
            } else {
                // Write call
                if (!walletClient || !address) {
                    toast.error("Please connect your wallet")
                    setResult({ success: false, error: "Wallet not connected" })
                    return
                }

                const { request } = await publicClient!.simulateContract({
                    address: contractAddress,
                    abi: [fn],
                    functionName: fn.name,
                    args: parsedArgs,
                    account: address,
                })

                const hash = await walletClient.writeContract(request)
                toast.success(`Transaction submitted: ${truncateAddress(hash)}`)
                setResult({ success: true, result: hash })
            }
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : "Unknown error"
            setResult({ success: false, error: errorMessage })
            // Only show toast for manual calls, not auto-queries
            if (hasAutoQueried || !canAutoQuery) {
                toast.error(`Error: ${errorMessage.slice(0, 100)}`)
            }
        } finally {
            setIsLoading(false)
        }
    }

    // Handle opening the collapsible - auto-query for no-arg read functions
    const handleOpenChange = (open: boolean) => {
        setIsOpen(open)
        if (open && canAutoQuery && !hasAutoQueried) {
            setHasAutoQueried(true)
            handleCall()
        }
    }

    const handleSimulate = async () => {
        setIsLoading(true)
        setResult(null)

        try {
            // Parse arguments (handles tuples recursively)
            const parsedArgs = fn.inputs.map((input, index) => {
                const basePath = input.name || `arg${index}`
                return parseArgsForParam(input as AbiParameterWithComponents, args, basePath)
            })

            const simulateResult = await publicClient?.simulateContract({
                address: contractAddress,
                abi: [fn],
                functionName: fn.name,
                args: parsedArgs,
                account: address || "0x0000000000000000000000000000000000000000",
            })

            setResult({ success: true, result: simulateResult?.result })
            toast.success("Simulation successful")
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : "Unknown error"
            setResult({ success: false, error: errorMessage })
            toast.error(`Simulation failed: ${errorMessage.slice(0, 100)}`)
        } finally {
            setIsLoading(false)
        }
    }

    const formatResult = (value: unknown): string => {
        if (value === null || value === undefined) return "null"
        if (typeof value === "bigint") return value.toString()
        if (typeof value === "object") return JSON.stringify(value, null, 2)
        return String(value)
    }

    return (
        <Collapsible open={isOpen} onOpenChange={handleOpenChange}>
            <CollapsibleTrigger asChild>
                <Button
                    variant="ghost"
                    className="flex w-full items-center justify-between p-4 hover:bg-muted"
                >
                    <div className="flex items-center gap-2">
                        <span
                            className={cn(
                                "rounded-full px-2 py-0.5 text-xs font-medium",
                                isReadFunction
                                    ? "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
                                    : "bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300"
                            )}
                        >
                            {isReadFunction ? "Read" : "Write"}
                        </span>
                        <span className="font-mono text-sm">{fn.name}</span>
                        {/* Show loading indicator in the header for auto-queries */}
                        {isLoading && canAutoQuery && (
                            <RefreshCw className="size-3 animate-spin text-muted-foreground" />
                        )}
                        {/* Show quick result preview for successful auto-queries */}
                        {result?.success && canAutoQuery && !isOpen && (
                            <span className="ml-2 max-w-[200px] truncate text-xs text-muted-foreground font-normal">
                                = {formatResult(result.result).slice(0, 50)}
                            </span>
                        )}
                    </div>
                    <ChevronDown
                        className={cn("size-4 transition-transform", isOpen && "rotate-180")}
                    />
                </Button>
            </CollapsibleTrigger>
            <CollapsibleContent className="border-t px-4 py-4">
                <div className="space-y-4">
                    {fn.inputs.length > 0 && (
                        <div className="space-y-3">
                            {fn.inputs.map((input, index) => (
                                <ParameterInput
                                    key={index}
                                    param={input as AbiParameterWithComponents}
                                    path={input.name || `arg${index}`}
                                    args={args}
                                    setArgs={setArgs}
                                />
                            ))}
                        </div>
                    )}

                    {!isReadFunction && (
                        <div className="flex gap-2">
                            <Button onClick={handleCall} disabled={isLoading} className="flex-1">
                                <Play className="mr-2 size-4" />
                                Execute
                            </Button>
                            <Button onClick={handleSimulate} disabled={isLoading} variant="outline">
                                Simulate
                            </Button>
                        </div>
                    )}

                    {/* For read functions with arguments, show a Query button */}
                    {isReadFunction && fn.inputs.length > 0 && (
                        <Button
                            onClick={handleCall}
                            disabled={isLoading}
                            className="w-full"
                            variant="secondary"
                        >
                            <Eye className="mr-2 size-4" />
                            Query
                        </Button>
                    )}

                    {result && (
                        <div
                            className={cn(
                                "mt-4 rounded-lg border p-4",
                                result.success
                                    ? "border-green-200 bg-green-50 dark:border-green-900 dark:bg-green-950"
                                    : "border-red-200 bg-red-50 dark:border-red-900 dark:bg-red-950"
                            )}
                        >
                            <div className="mb-2 flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    {result.success ? (
                                        <CheckCircle2 className="size-4 text-green-600" />
                                    ) : (
                                        <AlertCircle className="size-4 text-red-600" />
                                    )}
                                    <span className="text-sm font-medium">
                                        {result.success ? "Success" : "Error"}
                                    </span>
                                </div>
                                {isReadFunction && (
                                    <Button
                                        variant="ghost"
                                        size="sm"
                                        onClick={handleCall}
                                        disabled={isLoading}
                                        className="h-7 px-2 text-xs"
                                    >
                                        <RefreshCw
                                            className={cn(
                                                "size-3 mr-1",
                                                isLoading && "animate-spin"
                                            )}
                                        />
                                        Requery
                                    </Button>
                                )}
                            </div>
                            <pre className="overflow-x-auto text-xs">
                                {result.success ? formatResult(result.result) : result.error}
                            </pre>
                        </div>
                    )}
                </div>
            </CollapsibleContent>
        </Collapsible>
    )
}

interface AbiSectionProps {
    namedAbi: NamedAbi
    contractAddress: `0x${string}`
    chainId: number
}

function AbiSection({ namedAbi, contractAddress, chainId }: AbiSectionProps) {
    const readFunctions = useMemo(
        () =>
            namedAbi.abi.filter(
                (item): item is AbiFunction =>
                    item.type === "function" &&
                    (item.stateMutability === "view" || item.stateMutability === "pure")
            ),
        [namedAbi.abi]
    )

    const writeFunctions = useMemo(
        () =>
            namedAbi.abi.filter(
                (item): item is AbiFunction =>
                    item.type === "function" &&
                    item.stateMutability !== "view" &&
                    item.stateMutability !== "pure"
            ),
        [namedAbi.abi]
    )

    return (
        <div className="space-y-4">
            <div className="flex items-center gap-2">
                <h3 className="font-semibold text-sm">{namedAbi.name}</h3>
                <span className="text-xs text-muted-foreground">
                    ({readFunctions.length} read, {writeFunctions.length} write)
                </span>
            </div>
            <Tabs defaultValue="read">
                <TabsList className="w-full">
                    <TabsTrigger value="read" className="flex-1">
                        Read ({readFunctions.length})
                    </TabsTrigger>
                    <TabsTrigger value="write" className="flex-1">
                        Write ({writeFunctions.length})
                    </TabsTrigger>
                </TabsList>
                <TabsContent value="read" className="mt-4">
                    <ScrollArea className="h-fit">
                        <div className="divide-y rounded-lg border">
                            {readFunctions.map((fn, index) => (
                                <FunctionMethod
                                    key={index}
                                    fn={fn}
                                    contractAddress={contractAddress}
                                    chainId={chainId}
                                />
                            ))}
                        </div>
                    </ScrollArea>
                </TabsContent>
                <TabsContent value="write" className="mt-4">
                    <ScrollArea className="h-fit">
                        <div className="divide-y rounded-lg border">
                            {writeFunctions.map((fn, index) => (
                                <FunctionMethod
                                    key={index}
                                    fn={fn}
                                    contractAddress={contractAddress}
                                    chainId={chainId}
                                />
                            ))}
                        </div>
                    </ScrollArea>
                </TabsContent>
            </Tabs>
        </div>
    )
}

interface FunctionCardProps {
    contract: CoverageContract
}

export function FunctionCard({ contract }: FunctionCardProps) {
    // For CoverageProvider contracts, query interface support via ERC-165
    const { isLoading: isLoadingInterfaces, supports } = useCheckCoverageProviderSupport(
        contract.address,
        contract.chainId,
        contract.type === "CoverageProvider"
            ? [
                  "IEigenServiceManager",
                  "IAssetPriceOracleAndSwapper",
                  "IDiamondOwner",
                  "ICoverageProvider",
              ]
            : []
    )

    const namedAbis = useMemo(() => {
        // For CoverageProvider, use detected interfaces instead of additionalFields
        if (contract.type === "CoverageProvider") {
            return getAbisForCoverageProviderWithInterfaces(supports)
        }
        // For other contract types, use the standard method
        return getAbisForContractType(contract.type)
    }, [contract.type, supports])

    // Show loading state while detecting interfaces for CoverageProvider
    if (contract.type === "CoverageProvider" && isLoadingInterfaces) {
        return (
            <Card className="h-fit">
                <CardHeader>
                    <CardTitle>Contract Functions</CardTitle>
                    <CardDescription>Detecting supported interfaces...</CardDescription>
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
        <Card className="h-fit">
            <CardHeader>
                <CardTitle>Contract Functions</CardTitle>
                <CardDescription>
                    Read and write functions for {contract.name}
                    {contract.type === "CoverageProvider" && (
                        <span className="ml-2 text-xs">
                            (Detected:{" "}
                            {Object.entries(supports)
                                .filter(([, v]) => v)
                                .map(([k]) => k)
                                .join(", ") || "Base interfaces"}
                            )
                        </span>
                    )}
                </CardDescription>
            </CardHeader>
            <CardContent className="h-fit space-y-8">
                {namedAbis.map((namedAbi, index) => (
                    <AbiSection
                        key={index}
                        namedAbi={namedAbi}
                        contractAddress={contract.address}
                        chainId={contract.chainId}
                    />
                ))}
            </CardContent>
        </Card>
    )
}
