import { useMemo, useState, useEffect, useRef } from "react"
import { type Address, isAddress } from "viem"
import { RefreshCw, Loader2, Plus, CheckCircle2, Trash2, AlertCircle } from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iEigenServiceManagerAbi } from "@/generated/abis"
import { iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import { useCheckCoverageProviderSupport } from "@/hooks/use-interface-support"
import { CopyableAddress } from "@/components/ui/copyable-address"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface CoverageProviderInfoProps {
  contract: CoverageContract
}

/**
 * Component to display and manage strategy details
 */
function StrategyDetails({ 
  strategyAddress, 
  chainId 
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
                <span className="font-medium">{tokenName} ({tokenSymbol})</span>
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
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const prevSuccessRef = useRef(false)

  useEffect(() => {
    if (isSuccess && !prevSuccessRef.current) {
      onRemoveSuccess()
    }
    prevSuccessRef.current = isSuccess
  }, [isSuccess, onRemoveSuccess])

  const handleRemove = () => {
    writeContract({
      address: contractAddress,
      abi: iEigenServiceManagerAbi,
      functionName: "setStrategyWhitelist",
      args: [strategyAddress, false],
      chainId,
    }, {
      onSuccess: (hash) => {
        toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        toast.error(error.message.slice(0, 100))
      },
    })
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

export function CoverageProviderInfo({ contract }: CoverageProviderInfoProps) {
  const [newStrategyAddress, setNewStrategyAddress] = useState("")

  // Check if chainId is supported
  const isChainSupported = supportedChains.some(
    (chain) => chain.id === contract.chainId
  )
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
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

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
    return strategies.some(
      (s) => s.toLowerCase() === newStrategyAddress.toLowerCase()
    )
  }, [newStrategyAddress, strategies, isValidAddress])

  const handleAddStrategy = () => {
    if (!isValidAddress) {
      toast.error("Please enter a valid strategy address")
      return
    }

    if (isAlreadyWhitelisted) {
      toast.error("Strategy is already whitelisted")
      return
    }

    writeContract({
      address: contract.address,
      abi: iEigenServiceManagerAbi,
      functionName: "setStrategyWhitelist",
      args: [newStrategyAddress as `0x${string}`, true],
      chainId: supportedChainId,
    }, {
      onSuccess: (hash) => {
        toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        toast.error(error.message.slice(0, 100))
      },
    })
  }

  // Show loading state while checking interface support
  if (isCheckingInterface) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Coverage Provider</CardTitle>
          <CardDescription>
            Checking provider capabilities...
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center py-8">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        </CardContent>
      </Card>
    )
  }

  // If not an EigenLayer provider, show a message
  if (!isEigenProvider) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Coverage Provider</CardTitle>
          <CardDescription>
            Provider-specific management features
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <AlertCircle className="size-4" />
            No specific management interface available for this provider type.
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {/* Strategy Whitelist Management Card */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Strategy Whitelist</CardTitle>
              <CardDescription>
                Manage which EigenLayer strategies are whitelisted for this provider
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
                Enter an EigenLayer strategy address to whitelist. Strategy details will be shown below.
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
                  disabled={!isValidAddress || isAlreadyWhitelisted || isPending || isConfirming}
                >
                  {isPending || isConfirming ? (
                    <Loader2 className="mr-2 size-4 animate-spin" />
                  ) : (
                    <Plus className="mr-2 size-4" />
                  )}
                  {isPending ? "Confirm..." : isConfirming ? "Adding..." : "Add"}
                </Button>
              </div>
              {newStrategyAddress && !isValidAddress && (
                <p className="text-xs text-destructive">Please enter a valid Ethereum address</p>
              )}
              {isAlreadyWhitelisted && (
                <p className="text-xs text-amber-600">This strategy is already whitelisted</p>
              )}
            </div>

            {/* Strategy Preview */}
            {previewStrategy && !isAlreadyWhitelisted && (
              <div className="space-y-2">
                <Label>Strategy Preview</Label>
                <StrategyDetails strategyAddress={previewStrategy} chainId={supportedChainId} />
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
    </div>
  )
}

