import { useState } from "react"
import { Link } from "react-router-dom"
import { toast } from "sonner"
import {
  useAccount,
  useWalletClient,
} from "wagmi"
import { type Abi, type AbiFunction } from "viem"
import type { CoverageContract } from "@/types/contracts"
import { getPublicClientForChain } from "@/lib/wagmi"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import { ScrollArea } from "@/components/ui/scroll-area"
import { useContracts } from "@/hooks/use-contracts"
import { getAbiForContractType } from "@/utils/abi-utils"
import { cn, truncateAddress } from "@/lib/utils"
import { ChevronDown, Play, Eye, AlertCircle, CheckCircle2, RefreshCw } from "lucide-react"
import { ContractSelector } from "@/components/ContractSelector"
import { ContractSpecificInfo } from "@/components/ContractSpecificInfo"

interface FunctionCallResult {
  success: boolean
  result?: unknown
  error?: string
}

function FunctionCard({
  fn,
  contractAddress,
  abi,
  chainId,
}: {
  fn: AbiFunction
  contractAddress: `0x${string}`
  abi: Abi
  chainId: number
}) {
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

  const isReadFunction =
    fn.stateMutability === "view" || fn.stateMutability === "pure"
  
  // Check if this is a no-argument read function (can auto-query)
  const canAutoQuery = isReadFunction && fn.inputs.length === 0

  const handleCall = async () => {
    setIsLoading(true)
    setResult(null)

    try {
      // Parse arguments
      const parsedArgs = fn.inputs.map((input, index) => {
        const value = args[input.name || `arg${index}`] || ""
        if (input.type === "uint256" || input.type === "int256") {
          return BigInt(value || "0")
        }
        if (input.type === "bool") {
          return value.toLowerCase() === "true"
        }
        if (input.type.endsWith("[]")) {
          try {
            return JSON.parse(value)
          } catch {
            return []
          }
        }
        return value
      })

      if (isReadFunction) {
        // Read call
        const data = await publicClient?.readContract({
          address: contractAddress,
          abi,
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
          abi,
          functionName: fn.name,
          args: parsedArgs,
          account: address,
        })

        const hash = await walletClient.writeContract(request)
        toast.success(`Transaction submitted: ${truncateAddress(hash)}`)
        setResult({ success: true, result: hash })
      }
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error ? error.message : "Unknown error"
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
      const parsedArgs = fn.inputs.map((input, index) => {
        const value = args[input.name || `arg${index}`] || ""
        if (input.type === "uint256" || input.type === "int256") {
          return BigInt(value || "0")
        }
        if (input.type === "bool") {
          return value.toLowerCase() === "true"
        }
        if (input.type.endsWith("[]")) {
          try {
            return JSON.parse(value)
          } catch {
            return []
          }
        }
        return value
      })

      const simulateResult = await publicClient?.simulateContract({
        address: contractAddress,
        abi,
        functionName: fn.name,
        args: parsedArgs,
        account: address || "0x0000000000000000000000000000000000000000",
      })

      setResult({ success: true, result: simulateResult?.result })
      toast.success("Simulation successful")
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error ? error.message : "Unknown error"
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
            className={cn(
              "size-4 transition-transform",
              isOpen && "rotate-180"
            )}
          />
        </Button>
      </CollapsibleTrigger>
      <CollapsibleContent className="border-t px-4 py-4">
        <div className="space-y-4">
          {fn.inputs.length > 0 && (
            <div className="space-y-3">
              {fn.inputs.map((input, index) => (
                <div key={index}>
                  <Label className="text-xs">
                    {input.name || `arg${index}`}{" "}
                    <span className="text-muted-foreground">({input.type})</span>
                  </Label>
                  <Input
                    placeholder={input.type}
                    className="mt-1 font-mono text-sm"
                    value={args[input.name || `arg${index}`] || ""}
                    onChange={(e) =>
                      setArgs({
                        ...args,
                        [input.name || `arg${index}`]: e.target.value,
                      })
                    }
                  />
                </div>
              ))}
            </div>
          )}

          {!isReadFunction && (
            <div className="flex gap-2">
              <Button
                onClick={handleCall}
                disabled={isLoading}
                className="flex-1"
              >
                <Play className="mr-2 size-4" />
                Execute
              </Button>
              <Button
                onClick={handleSimulate}
                disabled={isLoading}
                variant="outline"
              >
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
                    <RefreshCw className={cn("size-3 mr-1", isLoading && "animate-spin")} />
                    Requery
                  </Button>
                )}
              </div>
              <pre className="overflow-x-auto text-xs">
                {result.success
                  ? formatResult(result.result)
                  : result.error}
              </pre>
            </div>
          )}
        </div>
      </CollapsibleContent>
    </Collapsible>
  )
}

export function InteractPage() {
  const { contracts } = useContracts()
  const [selectedContract, setSelectedContract] = useState<CoverageContract | null>(null)

  const abi = selectedContract
    ? (getAbiForContractType(selectedContract.type) as Abi)
    : []

  const readFunctions = abi.filter(
    (item): item is AbiFunction =>
      item.type === "function" &&
      (item.stateMutability === "view" || item.stateMutability === "pure")
  )

  const writeFunctions = abi.filter(
    (item): item is AbiFunction =>
      item.type === "function" &&
      item.stateMutability !== "view" &&
      item.stateMutability !== "pure"
  )

  if (contracts.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <h2 className="text-lg font-medium">No contracts yet</h2>
        <p className="mb-4 text-center text-sm text-muted-foreground">
          Add a contract to start interacting.
        </p>
        <Button asChild>
          <Link to="/add-contract">Add Contract</Link>
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Contract Interaction</h2>
        <p className="text-muted-foreground">
          Read and write to your contracts
        </p>
      </div>

      <ContractSelector
        title="Select Contract"
        description="Choose a contract to interact with"
        onContractChange={setSelectedContract}
      />

      {selectedContract && (
        <>
          <ContractSpecificInfo contract={selectedContract} />
          <Card className="h-fit">
          <CardHeader>
            <CardTitle>Contract Functions</CardTitle>
            <CardDescription>
              Read and write functions for {selectedContract.name}
            </CardDescription>
          </CardHeader>
          <CardContent className="h-fit">
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
                      <FunctionCard
                        key={index}
                        fn={fn}
                        contractAddress={selectedContract.address}
                        abi={abi}
                        chainId={selectedContract.chainId}
                      />
                    ))}
                  </div>
                </ScrollArea>
              </TabsContent>
              <TabsContent value="write" className="mt-4">
                <ScrollArea className="h-fit">
                  <div className="divide-y rounded-lg border">
                    {writeFunctions.map((fn, index) => (
                      <FunctionCard
                        key={index}
                        fn={fn}
                        contractAddress={selectedContract.address}
                        abi={abi}
                        chainId={selectedContract.chainId}
                      />
                    ))}
                  </div>
                </ScrollArea>
              </TabsContent>
            </Tabs>
          </CardContent>
        </Card>
        </>
      )}
    </div>
  )
}
