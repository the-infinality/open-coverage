import { useMemo, useState, useEffect } from "react"
import { RefreshCw, Loader2, User, Plus, Trash2, Settings, UserPlus, Layers, Shield, Key, Coins, ArrowRight, CheckCircle, AlertCircle } from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iEigenOperatorProxyAbi } from "@/generated/abis"
import { iPermissionControllerAbi, iAllocationManagerAbi, iDelegationManagerAbi, iStrategyManagerAbi, iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import { useContracts } from "@/hooks/use-contracts"
import { WalletRequirement } from "@/components/WalletRequirement"
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"

// EigenLayer addresses by chain
const EIGEN_ADDRESSES: Record<number, {
  allocationManager: `0x${string}`
  delegationManager: `0x${string}`
  strategyManager: `0x${string}`
  permissionController: `0x${string}`
  strategies: Record<string, `0x${string}`>
}> = {
  1: {
    allocationManager: "0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39",
    delegationManager: "0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A",
    strategyManager: "0x858646372CC42E1A627fcE94aa7A7033e7CF075A",
    permissionController: "0x25E5F8B1E7aDf44518d35D5B2271f114e081f0E5",
    strategies: {
      rETH: "0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2",
    },
  },
  11155111: {
    allocationManager: "0x42583067658071247ec8CE0A516A58f682002d07",
    delegationManager: "0xD4A7E1Bd8015057293f0D0A557088c286942e84b",
    strategyManager: "0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D",
    permissionController: "0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37",
    strategies: {
      WETH: "0x424246eF71b01ee33aA33aC590fd9a0855F5eFbc",
    },
  },
  31337: {
    allocationManager: "0x42583067658071247ec8CE0A516A58f682002d07",
    delegationManager: "0xD4A7E1Bd8015057293f0D0A557088c286942e84b",
    strategyManager: "0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D",
    permissionController: "0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37",
    strategies: {
      WETH: "0x424246eF71b01ee33aA33aC590fd9a0855F5eFbc",
    },
  },
}

interface EigenOperatorProxyManagementProps {
  contract: CoverageContract
}

interface StrategyAllocation {
  address: string
  magnitude: number // Stored as percentage (0-100)
}

type SupportedChainId = (typeof supportedChains)[number]["id"]

// Hook to filter contracts by chain
function useChainFilteredContracts(chainId: number) {
  const { contracts } = useContracts()

  const serviceManagers = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === chainId && 
             c.type === "CoverageProvider" && 
             c.additionalFields?.providerType === "EigenLayer"
    )
  }, [contracts, chainId])

  const coverageAgents = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === chainId && c.type === "CoverageAgent"
    )
  }, [contracts, chainId])

  return { serviceManagers, coverageAgents }
}

// Reusable Service Manager Select component
interface ServiceManagerSelectProps {
  value: string
  onValueChange: (value: string) => void
  chainId: number
  description?: string
}

function ServiceManagerSelect({ value, onValueChange, chainId, description }: ServiceManagerSelectProps) {
  const { serviceManagers } = useChainFilteredContracts(chainId)

  return (
    <div className="space-y-2">
      <Label>Service Manager</Label>
      <Select value={value} onValueChange={onValueChange}>
        <SelectTrigger className="font-mono">
          <SelectValue placeholder="Select service manager..." />
        </SelectTrigger>
        <SelectContent>
          {serviceManagers.length === 0 ? (
            <div className="px-2 py-4 text-center text-sm text-muted-foreground">
              No EigenLayer providers saved on this chain
            </div>
          ) : (
            serviceManagers.map((sm) => (
              <SelectItem key={sm.id} value={sm.address} className="font-mono">
                <span className="flex flex-col gap-0.5">
                  <span className="font-sans font-medium">{sm.name}</span>
                  <span className="text-xs text-muted-foreground">{sm.address.slice(0, 10)}...{sm.address.slice(-8)}</span>
                </span>
              </SelectItem>
            ))
          )}
        </SelectContent>
      </Select>
      {description && (
        <p className="text-xs text-muted-foreground">{description}</p>
      )}
    </div>
  )
}

// Reusable Coverage Agent Select component
interface CoverageAgentSelectProps {
  value: string
  onValueChange: (value: string) => void
  chainId: number
  description?: string
}

function CoverageAgentSelect({ value, onValueChange, chainId, description }: CoverageAgentSelectProps) {
  const { coverageAgents } = useChainFilteredContracts(chainId)

  return (
    <div className="space-y-2">
      <Label>Coverage Agent</Label>
      <Select value={value} onValueChange={onValueChange}>
        <SelectTrigger className="font-mono">
          <SelectValue placeholder="Select coverage agent..." />
        </SelectTrigger>
        <SelectContent>
          {coverageAgents.length === 0 ? (
            <div className="px-2 py-4 text-center text-sm text-muted-foreground">
              No coverage agents saved on this chain
            </div>
          ) : (
            coverageAgents.map((ca) => (
              <SelectItem key={ca.id} value={ca.address} className="font-mono">
                <span className="flex flex-col gap-0.5">
                  <span className="font-sans font-medium">{ca.name}</span>
                  <span className="text-xs text-muted-foreground">{ca.address.slice(0, 10)}...{ca.address.slice(-8)}</span>
                </span>
              </SelectItem>
            ))
          )}
        </SelectContent>
      </Select>
      {description && (
        <p className="text-xs text-muted-foreground">{description}</p>
      )}
    </div>
  )
}

// Pending Admin Card Component
function PendingAdminCard({ 
  contract, 
  chainId,
  eigenAddresses 
}: { 
  contract: CoverageContract
  chainId: SupportedChainId | undefined
  eigenAddresses: typeof EIGEN_ADDRESSES[number] | undefined
}) {
  const { address: connectedAddress } = useAccount()

  const { data: pendingAdmins, isLoading: isLoadingPending, refetch: refetchPending } = useReadContract({
    address: eigenAddresses?.permissionController,
    abi: iPermissionControllerAbi,
    functionName: "getPendingAdmins",
    args: [contract.address],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  const { data: admins, isLoading: isLoadingAdmins, refetch: refetchAdmins } = useReadContract({
    address: eigenAddresses?.permissionController,
    abi: iPermissionControllerAbi,
    functionName: "getAdmins",
    args: [contract.address],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  const { data: isPendingForConnected, refetch: refetchIsPending } = useReadContract({
    address: eigenAddresses?.permissionController,
    abi: iPermissionControllerAbi,
    functionName: "isPendingAdmin",
    args: [contract.address, connectedAddress as `0x${string}`],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId && !!connectedAddress,
    },
  })

  const { writeContract, isPending, data: hash } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  useEffect(() => {
    if (isSuccess) {
      refetchPending()
      refetchAdmins()
      refetchIsPending()
    }
  }, [isSuccess, refetchPending, refetchAdmins, refetchIsPending])

  const handleAcceptAdmin = () => {
    if (!eigenAddresses) return

    writeContract({
      address: eigenAddresses.permissionController,
      abi: iPermissionControllerAbi,
      functionName: "acceptAdmin",
      args: [contract.address],
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

  const isLoading = isLoadingPending || isLoadingAdmins

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Key className="size-5" />
              Admin Management
            </CardTitle>
            <CardDescription>
              View and manage admin permissions for this operator proxy
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => { refetchPending(); refetchAdmins() }}
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
      <CardContent className="space-y-4">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <>
            {/* Current Admins */}
            <div className="space-y-2">
              <Label className="text-sm font-medium flex items-center gap-2">
                <Shield className="size-4 text-green-500" />
                Active Admins ({admins?.length ?? 0})
              </Label>
              <div className="space-y-2">
                {admins && admins.length > 0 ? (
                  admins.map((admin) => (
                    <div key={admin} className="flex items-center gap-2 p-2 rounded-lg border bg-green-500/5 border-green-500/20">
                      <CheckCircle className="size-4 text-green-500" />
                      <span className="font-mono text-sm truncate flex-1">{admin}</span>
                      {connectedAddress?.toLowerCase() === admin.toLowerCase() && (
                        <Badge variant="secondary" className="text-xs">You</Badge>
                      )}
                    </div>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">No active admins</p>
                )}
              </div>
            </div>

            <Separator />

            {/* Pending Admins */}
            <div className="space-y-2">
              <Label className="text-sm font-medium flex items-center gap-2">
                <AlertCircle className="size-4 text-yellow-500" />
                Pending Admin Requests ({pendingAdmins?.length ?? 0})
              </Label>
              <div className="space-y-2">
                {pendingAdmins && pendingAdmins.length > 0 ? (
                  pendingAdmins.map((admin) => (
                    <div key={admin} className="flex items-center gap-2 p-2 rounded-lg border bg-yellow-500/5 border-yellow-500/20">
                      <span className="font-mono text-sm truncate flex-1">{admin}</span>
                      {connectedAddress?.toLowerCase() === admin.toLowerCase() && (
                        <Badge variant="outline" className="text-xs border-yellow-500/50 text-yellow-600">Pending for you</Badge>
                      )}
                    </div>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">No pending admin requests</p>
                )}
              </div>
            </div>

            {/* Accept Admin Button */}
            {isPendingForConnected && (
              <>
                <Separator />
                <div className="rounded-lg bg-yellow-500/10 border border-yellow-500/30 p-4 space-y-3">
                  <div className="flex items-start gap-3">
                    <Key className="size-5 text-yellow-600 mt-0.5" />
                    <div>
                      <h4 className="text-sm font-medium">Admin Request Pending</h4>
                      <p className="text-xs text-muted-foreground mt-1">
                        You have a pending admin request for this operator proxy. Accept to gain admin permissions.
                      </p>
                    </div>
                  </div>
                  <WalletRequirement requiredChainId={contract.chainId}>
                    <Button 
                      onClick={handleAcceptAdmin} 
                      disabled={isPending || isConfirming}
                      className="w-full"
                    >
                      {isPending ? (
                        <>
                          <Loader2 className="mr-2 size-4 animate-spin" />
                          Confirm in Wallet...
                        </>
                      ) : isConfirming ? (
                        <>
                          <Loader2 className="mr-2 size-4 animate-spin" />
                          Confirming...
                        </>
                      ) : (
                        <>
                          <CheckCircle className="mr-2 size-4" />
                          Accept Admin Role
                        </>
                      )}
                    </Button>
                  </WalletRequirement>
                </div>
              </>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}

// Operator Strategies Card Component
function OperatorStrategiesCard({ 
  contract, 
  chainId,
  eigenAddresses 
}: { 
  contract: CoverageContract
  chainId: SupportedChainId | undefined
  eigenAddresses: typeof EIGEN_ADDRESSES[number] | undefined
}) {
  // Get registered operator sets
  const { data: registeredSets, isLoading: isLoadingSets, refetch: refetchSets } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getRegisteredSets",
    args: [contract.address],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  // Get allocated sets
  const { data: allocatedSets, isLoading: isLoadingAllocated, refetch: refetchAllocated } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getAllocatedSets",
    args: [contract.address],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  // Get allocation delay
  const { data: allocationDelay, isLoading: isLoadingDelay, refetch: refetchDelay } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getAllocationDelay",
    args: [contract.address],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  const isLoading = isLoadingSets || isLoadingAllocated || isLoadingDelay

  const refetch = () => {
    refetchSets()
    refetchAllocated()
    refetchDelay()
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Layers className="size-5" />
              Operator Strategies
            </CardTitle>
            <CardDescription>
              View operator's registered sets and allocations
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={refetch}
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
      <CardContent className="space-y-4">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <>
            {/* Allocation Delay Info */}
            {allocationDelay && (
              <div className="rounded-lg bg-muted/50 p-3 flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium">Allocation Delay</p>
                  <p className="text-xs text-muted-foreground">
                    Time before allocations become slashable
                  </p>
                </div>
                <Badge variant={allocationDelay[0] ? "default" : "secondary"}>
                  {allocationDelay[0] ? `${allocationDelay[1]} blocks` : "Not set"}
                </Badge>
              </div>
            )}

            {/* Registered Operator Sets */}
            <div className="space-y-2">
              <Label className="text-sm font-medium flex items-center gap-2">
                <Shield className="size-4 text-blue-500" />
                Registered Operator Sets ({registeredSets?.length ?? 0})
              </Label>
              {registeredSets && registeredSets.length > 0 ? (
                <div className="space-y-2">
                  {registeredSets.map((set) => (
                    <OperatorSetCard 
                      key={`${set.avs}-${set.id}`}
                      operatorSet={set}
                      operatorAddress={contract.address}
                      chainId={chainId}
                      eigenAddresses={eigenAddresses}
                    />
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground p-3 rounded-lg border border-dashed">
                  No registered operator sets. Register with a coverage agent to start receiving allocations.
                </p>
              )}
            </div>

            <Separator />

            {/* Allocated Sets Summary */}
            <div className="space-y-2">
              <Label className="text-sm font-medium flex items-center gap-2">
                <Coins className="size-4 text-green-500" />
                Allocated Sets ({allocatedSets?.length ?? 0})
              </Label>
              {allocatedSets && allocatedSets.length > 0 ? (
                <div className="grid gap-2">
                  {allocatedSets.map((set) => (
                    <div 
                      key={`${set.avs}-${set.id}`}
                      className="flex items-center justify-between p-2 rounded-lg border bg-green-500/5 border-green-500/20"
                    >
                      <div className="flex items-center gap-2">
                        <div className="size-8 rounded-full bg-green-500/10 flex items-center justify-center">
                          <Layers className="size-4 text-green-500" />
                        </div>
                        <div>
                          <p className="text-xs text-muted-foreground">AVS</p>
                          <p className="font-mono text-xs">{set.avs.slice(0, 10)}...{set.avs.slice(-8)}</p>
                        </div>
                      </div>
                      <Badge variant="outline">Set #{set.id}</Badge>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground p-3 rounded-lg border border-dashed">
                  No allocations yet. Use the Allocate tab to allocate to strategies.
                </p>
              )}
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

// Operator Set Card with allocation details
function OperatorSetCard({
  operatorSet,
  operatorAddress,
  chainId,
  eigenAddresses,
}: {
  operatorSet: { avs: `0x${string}`; id: number }
  operatorAddress: `0x${string}`
  chainId: SupportedChainId | undefined
  eigenAddresses: typeof EIGEN_ADDRESSES[number] | undefined
}) {
  // Get strategies in this operator set
  const { data: strategies } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getStrategiesInOperatorSet",
    args: [operatorSet],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  // Get allocated strategies for this operator set
  const { data: allocatedStrategies } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getAllocatedStrategies",
    args: [operatorAddress, operatorSet],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  return (
    <div className="rounded-lg border p-3 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="size-8 rounded-full bg-blue-500/10 flex items-center justify-center">
            <Layers className="size-4 text-blue-500" />
          </div>
          <div>
            <p className="text-sm font-medium">Operator Set #{operatorSet.id}</p>
            <p className="text-xs text-muted-foreground font-mono">{operatorSet.avs.slice(0, 10)}...{operatorSet.avs.slice(-8)}</p>
          </div>
        </div>
        <Badge variant="secondary" className="text-xs">
          {strategies?.length ?? 0} strategies
        </Badge>
      </div>

      {allocatedStrategies && allocatedStrategies.length > 0 && (
        <div className="space-y-2 pt-2 border-t">
          <p className="text-xs font-medium text-muted-foreground">Allocated Strategies</p>
          <div className="grid gap-1">
            {allocatedStrategies.map((strategy) => (
              <StrategyAllocationRow
                key={strategy}
                strategy={strategy}
                operatorAddress={operatorAddress}
                operatorSet={operatorSet}
                chainId={chainId}
                eigenAddresses={eigenAddresses}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// Strategy allocation row with magnitude
function StrategyAllocationRow({
  strategy,
  operatorAddress,
  operatorSet,
  chainId,
  eigenAddresses,
}: {
  strategy: `0x${string}`
  operatorAddress: `0x${string}`
  operatorSet: { avs: `0x${string}`; id: number }
  chainId: SupportedChainId | undefined
  eigenAddresses: typeof EIGEN_ADDRESSES[number] | undefined
}) {
  const { data: allocation } = useReadContract({
    address: eigenAddresses?.allocationManager,
    abi: iAllocationManagerAbi,
    functionName: "getAllocation",
    args: [operatorAddress, operatorSet, strategy],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId,
    },
  })

  const formatMagnitude = (magnitude: bigint) => {
    const percentage = Number(magnitude) / 1e16
    return percentage.toFixed(2) + "%"
  }

  return (
    <div className="flex items-center justify-between py-1 px-2 rounded bg-muted/30 text-xs">
      <span className="font-mono text-muted-foreground">{strategy.slice(0, 8)}...{strategy.slice(-6)}</span>
      {allocation && (
        <span className="font-medium">{formatMagnitude(allocation.currentMagnitude)}</span>
      )}
    </div>
  )
}

// Staking Card Component - for delegating to operator and depositing into strategies
function StakingCard({ 
  contract, 
  chainId,
  eigenAddresses 
}: { 
  contract: CoverageContract
  chainId: SupportedChainId | undefined
  eigenAddresses: typeof EIGEN_ADDRESSES[number] | undefined
}) {
  const { address: connectedAddress } = useAccount()
  const [selectedStrategy, setSelectedStrategy] = useState<string>("")
  const [depositAmount, setDepositAmount] = useState<string>("")

  // Check if connected user is delegated
  const { data: isDelegated, refetch: refetchDelegated } = useReadContract({
    address: eigenAddresses?.delegationManager,
    abi: iDelegationManagerAbi,
    functionName: "isDelegated",
    args: [connectedAddress as `0x${string}`],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId && !!connectedAddress,
    },
  })

  // Check who the user is delegated to
  const { data: delegatedTo, refetch: refetchDelegatedTo } = useReadContract({
    address: eigenAddresses?.delegationManager,
    abi: iDelegationManagerAbi,
    functionName: "delegatedTo",
    args: [connectedAddress as `0x${string}`],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId && !!connectedAddress && isDelegated,
    },
  })

  // Get user's current deposits
  const { data: deposits, refetch: refetchDeposits } = useReadContract({
    address: eigenAddresses?.strategyManager,
    abi: iStrategyManagerAbi,
    functionName: "getDeposits",
    args: [connectedAddress as `0x${string}`],
    chainId,
    query: {
      enabled: !!eigenAddresses && !!chainId && !!connectedAddress,
    },
  })

  // Get strategy underlying token
  const { data: underlyingToken } = useReadContract({
    address: selectedStrategy as `0x${string}`,
    abi: iStrategyAbi,
    functionName: "underlyingToken",
    chainId,
    query: {
      enabled: !!selectedStrategy && !!chainId,
    },
  })

  // Get token balance
  const { data: tokenBalance, refetch: refetchBalance } = useReadContract({
    address: underlyingToken as `0x${string}`,
    abi: ierc20Abi,
    functionName: "balanceOf",
    args: [connectedAddress as `0x${string}`],
    chainId,
    query: {
      enabled: !!underlyingToken && !!chainId && !!connectedAddress,
    },
  })

  // Get token allowance
  const { data: tokenAllowance, refetch: refetchAllowance } = useReadContract({
    address: underlyingToken as `0x${string}`,
    abi: ierc20Abi,
    functionName: "allowance",
    args: [connectedAddress as `0x${string}`, eigenAddresses?.strategyManager as `0x${string}`],
    chainId,
    query: {
      enabled: !!underlyingToken && !!chainId && !!connectedAddress && !!eigenAddresses,
    },
  })

  // Get token decimals and symbol
  const { data: tokenDecimals } = useReadContract({
    address: underlyingToken as `0x${string}`,
    abi: ierc20Abi,
    functionName: "decimals",
    chainId,
    query: {
      enabled: !!underlyingToken && !!chainId,
    },
  })

  const { data: tokenSymbol } = useReadContract({
    address: underlyingToken as `0x${string}`,
    abi: ierc20Abi,
    functionName: "symbol",
    chainId,
    query: {
      enabled: !!underlyingToken && !!chainId,
    },
  })

  const { writeContract: writeDelegation, isPending: isDelegating, data: delegateHash } = useWriteContract()
  const { isLoading: isDelegateConfirming, isSuccess: isDelegateSuccess } = useWaitForTransactionReceipt({ hash: delegateHash })

  const { writeContract: writeApprove, isPending: isApproving, data: approveHash } = useWriteContract()
  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveHash })

  const { writeContract: writeDeposit, isPending: isDepositing, data: depositHash } = useWriteContract()
  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } = useWaitForTransactionReceipt({ hash: depositHash })

  useEffect(() => {
    if (isDelegateSuccess || isDepositSuccess || isApproveSuccess) {
      refetchDelegated()
      refetchDelegatedTo()
      refetchDeposits()
      refetchBalance()
      refetchAllowance()
    }
  }, [isDelegateSuccess, isDepositSuccess, isApproveSuccess])

  const handleDelegate = () => {
    if (!eigenAddresses) return

    writeDelegation({
      address: eigenAddresses.delegationManager,
      abi: iDelegationManagerAbi,
      functionName: "delegateTo",
      args: [
        contract.address,
        { signature: "0x" as `0x${string}`, expiry: BigInt(0) },
        "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
      ],
      chainId,
    }, {
      onSuccess: (hash) => {
        toast.success(`Delegation transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        toast.error(error.message.slice(0, 100))
      },
    })
  }

  const handleApprove = () => {
    if (!underlyingToken || !eigenAddresses || !depositAmount) return

    const decimals = tokenDecimals ?? 18
    const amountWei = BigInt(Math.floor(parseFloat(depositAmount) * 10 ** decimals))

    writeApprove({
      address: underlyingToken as `0x${string}`,
      abi: ierc20Abi,
      functionName: "approve",
      args: [eigenAddresses.strategyManager, amountWei],
      chainId,
    }, {
      onSuccess: (hash) => {
        toast.success(`Approval transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        toast.error(error.message.slice(0, 100))
      },
    })
  }

  const handleDeposit = () => {
    if (!eigenAddresses || !selectedStrategy || !underlyingToken || !depositAmount) return

    const decimals = tokenDecimals ?? 18
    const amountWei = BigInt(Math.floor(parseFloat(depositAmount) * 10 ** decimals))

    writeDeposit({
      address: eigenAddresses.strategyManager,
      abi: iStrategyManagerAbi,
      functionName: "depositIntoStrategy",
      args: [selectedStrategy as `0x${string}`, underlyingToken as `0x${string}`, amountWei],
      chainId,
    }, {
      onSuccess: (hash) => {
        toast.success(`Deposit transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        toast.error(error.message.slice(0, 100))
      },
    })
  }

  const formatBalance = (balance: bigint | undefined, decimals: number | undefined) => {
    if (!balance) return "0"
    const dec = decimals ?? 18
    return (Number(balance) / 10 ** dec).toFixed(6)
  }

  const needsApproval = useMemo(() => {
    if (!tokenAllowance || !depositAmount || !tokenDecimals) return false
    const decimals = tokenDecimals ?? 18
    const amountWei = BigInt(Math.floor(parseFloat(depositAmount || "0") * 10 ** decimals))
    return amountWei > tokenAllowance
  }, [tokenAllowance, depositAmount, tokenDecimals])

  const isDelegatedToThis = delegatedTo?.toLowerCase() === contract.address.toLowerCase()

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Coins className="size-5" />
              Stake to Operator
            </CardTitle>
            <CardDescription>
              Delegate and deposit into strategies to support this operator
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <WalletRequirement requiredChainId={contract.chainId}>
          {/* Delegation Status */}
          <div className="rounded-lg border p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <User className="size-5 text-muted-foreground" />
                <span className="font-medium">Delegation Status</span>
              </div>
              {isDelegated ? (
                isDelegatedToThis ? (
                  <Badge className="bg-green-500">Delegated to this operator</Badge>
                ) : (
                  <Badge variant="secondary">Delegated to another operator</Badge>
                )
              ) : (
                <Badge variant="outline">Not delegated</Badge>
              )}
            </div>

            {isDelegated && delegatedTo && !isDelegatedToThis && (
              <div className="text-xs text-muted-foreground">
                Currently delegated to: <span className="font-mono">{delegatedTo.slice(0, 10)}...{delegatedTo.slice(-8)}</span>
              </div>
            )}

            {!isDelegated && (
              <Button 
                onClick={handleDelegate} 
                disabled={isDelegating || isDelegateConfirming}
                className="w-full"
              >
                {isDelegating ? (
                  <>
                    <Loader2 className="mr-2 size-4 animate-spin" />
                    Confirm in Wallet...
                  </>
                ) : isDelegateConfirming ? (
                  <>
                    <Loader2 className="mr-2 size-4 animate-spin" />
                    Confirming...
                  </>
                ) : (
                  <>
                    <ArrowRight className="mr-2 size-4" />
                    Delegate to this Operator
                  </>
                )}
              </Button>
            )}
          </div>

          <Separator />

          {/* Strategy Deposit */}
          <div className="space-y-4">
            <div className="rounded-lg bg-muted/50 p-3">
              <h4 className="text-sm font-medium">Deposit into Strategy</h4>
              <p className="text-xs text-muted-foreground mt-1">
                Deposit tokens into an EigenLayer strategy. Your deposit will be delegated to the operator you're delegated to.
              </p>
            </div>

            <div className="space-y-2">
              <Label>Strategy</Label>
              <Select value={selectedStrategy} onValueChange={setSelectedStrategy}>
                <SelectTrigger className="font-mono">
                  <SelectValue placeholder="Select strategy..." />
                </SelectTrigger>
                <SelectContent>
                  {eigenAddresses && Object.entries(eigenAddresses.strategies).map(([name, address]) => (
                    <SelectItem key={address} value={address} className="font-mono">
                      <span className="flex flex-col gap-0.5">
                        <span className="font-sans font-medium">{name}</span>
                        <span className="text-xs text-muted-foreground">{address.slice(0, 10)}...{address.slice(-8)}</span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {selectedStrategy && underlyingToken && (
              <>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <Label>Amount</Label>
                    <span className="text-xs text-muted-foreground">
                      Balance: {formatBalance(tokenBalance, tokenDecimals)} {tokenSymbol}
                    </span>
                  </div>
                  <Input
                    type="number"
                    placeholder="0.0"
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                  />
                </div>

                {needsApproval ? (
                  <Button 
                    onClick={handleApprove} 
                    disabled={isApproving || isApproveConfirming || !depositAmount}
                    className="w-full"
                  >
                    {isApproving ? (
                      <>
                        <Loader2 className="mr-2 size-4 animate-spin" />
                        Confirm in Wallet...
                      </>
                    ) : isApproveConfirming ? (
                      <>
                        <Loader2 className="mr-2 size-4 animate-spin" />
                        Confirming...
                      </>
                    ) : (
                      <>
                        <CheckCircle className="mr-2 size-4" />
                        Approve {tokenSymbol}
                      </>
                    )}
                  </Button>
                ) : (
                  <Button 
                    onClick={handleDeposit} 
                    disabled={isDepositing || isDepositConfirming || !depositAmount}
                    className="w-full"
                  >
                    {isDepositing ? (
                      <>
                        <Loader2 className="mr-2 size-4 animate-spin" />
                        Confirm in Wallet...
                      </>
                    ) : isDepositConfirming ? (
                      <>
                        <Loader2 className="mr-2 size-4 animate-spin" />
                        Confirming...
                      </>
                    ) : (
                      <>
                        <Coins className="mr-2 size-4" />
                        Deposit {tokenSymbol}
                      </>
                    )}
                  </Button>
                )}
              </>
            )}
          </div>

          {/* Current Deposits */}
          {deposits && deposits[0].length > 0 && (
            <>
              <Separator />
              <div className="space-y-2">
                <Label className="text-sm font-medium">Your Current Deposits</Label>
                <div className="space-y-2">
                  {deposits[0].map((strategy, index) => (
                    <div key={strategy} className="flex items-center justify-between p-2 rounded-lg border bg-muted/30">
                      <span className="font-mono text-xs">{strategy.slice(0, 10)}...{strategy.slice(-8)}</span>
                      <span className="text-sm font-medium">{formatBalance(deposits[1][index], 18)} shares</span>
                    </div>
                  ))}
                </div>
              </div>
            </>
          )}
        </WalletRequirement>
      </CardContent>
    </Card>
  )
}

function RegisterCoverageAgentForm({ contract, chainId }: { contract: CoverageContract; chainId: SupportedChainId | undefined }) {
  const [serviceManager, setServiceManager] = useState("")
  const [coverageAgent, setCoverageAgent] = useState("")
  const [rewardsSplit, setRewardsSplit] = useState(0) // Stored as percentage (0-100)

  const { writeContract, isPending, data: hash } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!serviceManager || !coverageAgent) {
      toast.error("Please fill in all fields")
      return
    }

    // Convert percentage (0-100) to basis points (0-10000)
    const rewardsSplitBps = Math.floor(rewardsSplit * 100)

    writeContract({
      address: contract.address,
      abi: iEigenOperatorProxyAbi,
      functionName: "registerCoverageAgent",
      args: [serviceManager as `0x${string}`, coverageAgent as `0x${string}`, rewardsSplitBps],
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
    <form onSubmit={handleSubmit} className="space-y-4">
      <ServiceManagerSelect
        value={serviceManager}
        onValueChange={setServiceManager}
        chainId={contract.chainId}
        description="The EigenLayer service manager contract address"
      />

      <CoverageAgentSelect
        value={coverageAgent}
        onValueChange={setCoverageAgent}
        chainId={contract.chainId}
        description="The coverage agent contract to register with"
      />

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label>Rewards Split</Label>
          <span className="text-sm font-medium tabular-nums">{rewardsSplit}%</span>
        </div>
        <Slider
          value={rewardsSplit}
          onChange={setRewardsSplit}
          min={0}
          max={100}
          step={1}
        />
        <p className="text-xs text-muted-foreground">
          Percentage of rewards kept by operator (0% = all to restakers, 100% = all to operator)
        </p>
      </div>

      <Button type="submit" disabled={isPending || isConfirming} className="w-full">
        {isPending ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirm in Wallet...
          </>
        ) : isConfirming ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirming...
          </>
        ) : (
          <>
            <UserPlus className="mr-2 size-4" />
            Register Coverage Agent
          </>
        )}
      </Button>

      {isSuccess && (
        <p className="text-sm text-green-600 text-center">
          Coverage agent registered successfully!
        </p>
      )}
    </form>
  )
}

function AllocateForm({ contract, chainId }: { contract: CoverageContract; chainId: SupportedChainId | undefined }) {
  const [serviceManager, setServiceManager] = useState("")
  const [coverageAgent, setCoverageAgent] = useState("")
  const [strategies, setStrategies] = useState<StrategyAllocation[]>([
    { address: "", magnitude: 0 }
  ])

  const { writeContract, isPending, data: hash } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const addStrategy = () => {
    setStrategies([...strategies, { address: "", magnitude: 0 }])
  }

  const removeStrategy = (index: number) => {
    if (strategies.length > 1) {
      setStrategies(strategies.filter((_, i) => i !== index))
    }
  }

  const updateStrategyAddress = (index: number, value: string) => {
    const newStrategies = [...strategies]
    newStrategies[index].address = value
    setStrategies(newStrategies)
  }

  const updateStrategyMagnitude = (index: number, value: number) => {
    const newStrategies = [...strategies]
    newStrategies[index].magnitude = value
    setStrategies(newStrategies)
  }

  // Convert percentage (0-100) to WAD format (1e18 = 100%)
  const percentageToWad = (percentage: number): bigint => {
    return BigInt(Math.floor(percentage * 1e16)) // percentage * 1e18 / 100
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!serviceManager || !coverageAgent) {
      toast.error("Please fill in service manager and coverage agent")
      return
    }

    const validStrategies = strategies.filter(s => s.address && s.magnitude > 0)
    if (validStrategies.length === 0) {
      toast.error("Please add at least one strategy allocation with magnitude > 0")
      return
    }

    const strategyAddresses = validStrategies.map(s => s.address as `0x${string}`)
    const magnitudes = validStrategies.map(s => percentageToWad(s.magnitude))

    writeContract({
      address: contract.address,
      abi: iEigenOperatorProxyAbi,
      functionName: "allocate",
      args: [serviceManager as `0x${string}`, coverageAgent as `0x${string}`, strategyAddresses, magnitudes],
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
    <form onSubmit={handleSubmit} className="space-y-4">
      <ServiceManagerSelect
        value={serviceManager}
        onValueChange={setServiceManager}
        chainId={contract.chainId}
      />

      <CoverageAgentSelect
        value={coverageAgent}
        onValueChange={setCoverageAgent}
        chainId={contract.chainId}
      />

      <Separator />

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label>Strategy Allocations</Label>
          <Button type="button" variant="outline" size="sm" onClick={addStrategy}>
            <Plus className="mr-1 size-3" />
            Add Strategy
          </Button>
        </div>
        
        <p className="text-xs text-muted-foreground">
          Configure which strategies to allocate to and their allocation percentages
        </p>

        <div className="space-y-3">
          {strategies.map((strategy, index) => (
            <div key={index} className="flex gap-2 items-start p-3 rounded-lg border bg-muted/30">
              <div className="flex-1 space-y-3">
                <Input
                  placeholder="Strategy address (0x...)"
                  value={strategy.address}
                  onChange={(e) => updateStrategyAddress(index, e.target.value)}
                  className="font-mono text-sm"
                />
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-muted-foreground">Allocation</span>
                    <span className="text-sm font-medium tabular-nums">{strategy.magnitude}%</span>
                  </div>
                  <Slider
                    value={strategy.magnitude}
                    onChange={(value) => updateStrategyMagnitude(index, value)}
                    min={0}
                    max={100}
                    step={1}
                  />
                </div>
              </div>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                onClick={() => removeStrategy(index)}
                disabled={strategies.length === 1}
                className="shrink-0 text-muted-foreground hover:text-destructive"
              >
                <Trash2 className="size-4" />
              </Button>
            </div>
          ))}
        </div>
      </div>

      <Button type="submit" disabled={isPending || isConfirming} className="w-full">
        {isPending ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirm in Wallet...
          </>
        ) : isConfirming ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirming...
          </>
        ) : (
          <>
            <Layers className="mr-2 size-4" />
            Allocate to Strategies
          </>
        )}
      </Button>

      {isSuccess && (
        <p className="text-sm text-green-600 text-center">
          Allocation successful!
        </p>
      )}
    </form>
  )
}

function UpdateMetadataForm({ contract, chainId }: { contract: CoverageContract; chainId: SupportedChainId | undefined }) {
  const [metadataUri, setMetadataUri] = useState("")

  const { writeContract, isPending, data: hash } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!metadataUri) {
      toast.error("Please enter a metadata URI")
      return
    }

    writeContract({
      address: contract.address,
      abi: iEigenOperatorProxyAbi,
      functionName: "updateOperatorMetadataURI",
      args: [metadataUri],
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
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="metadataUri">Metadata URI</Label>
        <Input
          id="metadataUri"
          placeholder="https://example.com/operator-metadata.json"
          value={metadataUri}
          onChange={(e) => setMetadataUri(e.target.value)}
        />
        <p className="text-xs text-muted-foreground">
          A URL pointing to a JSON file containing operator metadata (name, description, logo, etc.)
        </p>
      </div>

      <Button type="submit" disabled={isPending || isConfirming} className="w-full">
        {isPending ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirm in Wallet...
          </>
        ) : isConfirming ? (
          <>
            <Loader2 className="mr-2 size-4 animate-spin" />
            Confirming...
          </>
        ) : (
          <>
            <Settings className="mr-2 size-4" />
            Update Metadata
          </>
        )}
      </Button>

      {isSuccess && (
        <p className="text-sm text-green-600 text-center">
          Metadata updated successfully!
        </p>
      )}
    </form>
  )
}

export function EigenOperatorProxyManagement({ contract }: EigenOperatorProxyManagementProps) {
  const isChainSupported = supportedChains.some(
    (chain) => chain.id === contract.chainId
  )

  const chainId = isChainSupported
    ? (contract.chainId as (typeof supportedChains)[number]["id"])
    : undefined

  const eigenAddresses = chainId ? EIGEN_ADDRESSES[chainId] : undefined

  const {
    data: handler,
    isLoading,
    isError,
    refetch,
  } = useReadContract({
    address: contract.address,
    abi: iEigenOperatorProxyAbi,
    functionName: "handler",
    chainId,
    query: {
      enabled: isChainSupported,
    },
  })

  return (
    <div className="space-y-4">
      {/* Handler Info Card */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Operator Proxy Info</CardTitle>
              <CardDescription>
                Current configuration for this operator proxy
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
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="size-6 animate-spin text-muted-foreground" />
            </div>
          ) : isError ? (
            <div className="py-8 text-center text-sm text-destructive">
              Failed to fetch handler
            </div>
          ) : (
            <div className="flex items-center gap-3 rounded-lg border p-4">
              <div className="flex size-10 items-center justify-center rounded-full bg-primary/10">
                <User className="size-5 text-primary" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-muted-foreground">Handler</p>
                <p className="font-mono text-sm truncate" title={handler}>
                  {handler}
                </p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Admin Management Card */}
      {eigenAddresses && (
        <PendingAdminCard 
          contract={contract} 
          chainId={chainId} 
          eigenAddresses={eigenAddresses} 
        />
      )}

      {/* Operator Strategies Card */}
      {eigenAddresses && (
        <OperatorStrategiesCard 
          contract={contract} 
          chainId={chainId} 
          eigenAddresses={eigenAddresses} 
        />
      )}

      {/* Staking Card */}
      {eigenAddresses && (
        <StakingCard 
          contract={contract} 
          chainId={chainId} 
          eigenAddresses={eigenAddresses} 
        />
      )}

      {/* Management Actions Card */}
      <Card>
        <CardHeader>
          <CardTitle>Management Actions</CardTitle>
          <CardDescription>
            Execute write operations on the operator proxy
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <WalletRequirement requiredChainId={contract.chainId}>
            <Tabs defaultValue="register" className="w-full">
              <TabsList className="grid w-full grid-cols-3">
                <TabsTrigger value="register" className="text-xs sm:text-sm">
                  <UserPlus className="mr-1 size-3 hidden sm:inline" />
                  Register
                </TabsTrigger>
                <TabsTrigger value="allocate" className="text-xs sm:text-sm">
                  <Layers className="mr-1 size-3 hidden sm:inline" />
                  Allocate
                </TabsTrigger>
                <TabsTrigger value="metadata" className="text-xs sm:text-sm">
                  <Settings className="mr-1 size-3 hidden sm:inline" />
                  Metadata
                </TabsTrigger>
              </TabsList>

              <TabsContent value="register" className="mt-4">
                <div className="space-y-4">
                  <div className="rounded-lg bg-muted/50 p-3">
                    <h4 className="text-sm font-medium">Register Coverage Agent</h4>
                    <p className="text-xs text-muted-foreground mt-1">
                      Register this operator to provide coverage for a specific coverage agent through an EigenLayer service manager.
                    </p>
                  </div>
                  <RegisterCoverageAgentForm contract={contract} chainId={chainId} />
                </div>
              </TabsContent>

              <TabsContent value="allocate" className="mt-4">
                <div className="space-y-4">
                  <div className="rounded-lg bg-muted/50 p-3">
                    <h4 className="text-sm font-medium">Allocate to Strategies</h4>
                    <p className="text-xs text-muted-foreground mt-1">
                      Allocate stake to strategies for a coverage agent. This can only be called after the allocation delay period (~17.5 days).
                    </p>
                  </div>
                  <AllocateForm contract={contract} chainId={chainId} />
                </div>
              </TabsContent>

              <TabsContent value="metadata" className="mt-4">
                <div className="space-y-4">
                  <div className="rounded-lg bg-muted/50 p-3">
                    <h4 className="text-sm font-medium">Update Operator Metadata</h4>
                    <p className="text-xs text-muted-foreground mt-1">
                      Update the metadata URI for this operator. The URI should point to a JSON file containing operator information.
                    </p>
                  </div>
                  <UpdateMetadataForm contract={contract} chainId={chainId} />
                </div>
              </TabsContent>
            </Tabs>
          </WalletRequirement>
        </CardContent>
      </Card>
    </div>
  )
}
