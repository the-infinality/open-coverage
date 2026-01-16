import { useMemo, useState } from "react"
import { RefreshCw, Loader2, User, Plus, Trash2, Settings, UserPlus, Layers } from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iEigenOperatorProxyAbi } from "@/generated/abis"
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
          ✓ Coverage agent registered successfully!
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
          ✓ Allocation successful!
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
          ✓ Metadata updated successfully!
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
