import { useState, useMemo } from "react"
import { useNavigate } from "react-router-dom"
import { 
  RefreshCw, 
  Loader2, 
  User, 
  Plus, 
  ExternalLink,
  Rocket,
  Users
} from "lucide-react"
import { 
  useAccount, 
  useWaitForTransactionReceipt,
  useDeployContract
} from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { 
  eigenOperatorProxyAbi, 
  eigenOperatorProxyBytecode 
} from "@/generated/abis"
import { supportedChains } from "@/lib/wagmi"
import { getEigenAddresses, isEigenLayerSupported } from "@/lib/eigen-config"
import { useContracts } from "@/hooks/use-contracts"
import { WalletRequirement } from "@/components/WalletRequirement"
import { ContractCard } from "@/components/ContractCard"
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
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"

interface EigenProviderOperatorManagementProps {
  contract: CoverageContract
}

function DeployOperatorProxyDialog({ 
  chainId, 
  onSuccess 
}: { 
  chainId: number
  onSuccess: (address: string, name: string) => void
}) {
  const [operatorName, setOperatorName] = useState("")
  const [metadataUri, setMetadataUri] = useState("https://coverage.example.com/operator.json")
  const [open, setOpen] = useState(false)
  const { address: connectedAddress } = useAccount()

  const eigenAddresses = getEigenAddresses(chainId)
  
  const { deployContract, isPending, data: hash, reset } = useDeployContract()
  const { 
    isLoading: isConfirming, 
    isSuccess,
    data: receipt 
  } = useWaitForTransactionReceipt({ hash })

  // When deployment succeeds, add the contract and close
  if (isSuccess && receipt?.contractAddress) {
    const contractAddress = receipt.contractAddress
    const name = operatorName || `Operator Proxy ${contractAddress.slice(0, 8)}`
    
    // Delay to allow the toast to show
    setTimeout(() => {
      onSuccess(contractAddress, name)
      setOpen(false)
      setOperatorName("")
      reset()
    }, 500)
    
    toast.success(`Operator Proxy deployed at ${contractAddress.slice(0, 10)}...`)
  }

  const handleDeploy = () => {
    if (!connectedAddress) {
      toast.error("Please connect your wallet")
      return
    }

    if (!eigenAddresses) {
      toast.error("EigenLayer not supported on this chain")
      return
    }

    // Construct the EigenAddresses struct
    const eigenAddressesStruct = {
      allocationManager: eigenAddresses.allocationManager,
      delegationManager: eigenAddresses.delegationManager,
      strategyManager: eigenAddresses.strategyManager,
      rewardsCoordinator: eigenAddresses.rewardsCoordinator,
      permissionController: eigenAddresses.permissionController,
    }

    deployContract({
      abi: eigenOperatorProxyAbi,
      bytecode: eigenOperatorProxyBytecode,
      args: [eigenAddressesStruct, connectedAddress, metadataUri],
      chainId: chainId as (typeof supportedChains)[number]["id"],
    }, {
      onSuccess: (hash) => {
        toast.success(`Deployment transaction submitted: ${hash.slice(0, 10)}...`)
      },
      onError: (error) => {
        console.error("Deployment error:", error)
        toast.error(error.message.slice(0, 100))
      },
    })
  }

  const isDeploying = isPending || isConfirming

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="mr-2 size-4" />
          Deploy New Operator
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Deploy EigenOperatorProxy</DialogTitle>
          <DialogDescription>
            Deploy a new EigenOperatorProxy contract. You will be set as the handler 
            (admin) for this operator proxy.
          </DialogDescription>
        </DialogHeader>
        
        <div className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="operatorName">Operator Name (optional)</Label>
            <Input
              id="operatorName"
              placeholder="My Operator Proxy"
              value={operatorName}
              onChange={(e) => setOperatorName(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              A friendly name for this operator proxy (for display only)
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="metadataUri">Operator Metadata URI</Label>
            <Input
              id="metadataUri"
              placeholder="https://example.com/operator.json"
              value={metadataUri}
              onChange={(e) => setMetadataUri(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              A URL pointing to a JSON file containing operator metadata
            </p>
          </div>

          <Separator />

          <div className="rounded-lg bg-muted/50 p-3">
            <div className="flex items-center gap-2">
              <User className="size-4 text-muted-foreground" />
              <span className="text-sm font-medium">Handler (You)</span>
            </div>
            <p className="mt-1 font-mono text-xs text-muted-foreground truncate">
              {connectedAddress || "Not connected"}
            </p>
          </div>

          {eigenAddresses && (
            <div className="rounded-lg border p-3 text-xs space-y-1">
              <p className="font-medium mb-2">EigenLayer Addresses</p>
              <p className="text-muted-foreground">
                <span className="font-medium">Allocation:</span>{" "}
                <span className="font-mono">{eigenAddresses.allocationManager.slice(0, 10)}...</span>
              </p>
              <p className="text-muted-foreground">
                <span className="font-medium">Delegation:</span>{" "}
                <span className="font-mono">{eigenAddresses.delegationManager.slice(0, 10)}...</span>
              </p>
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2">
          <Button 
            variant="outline" 
            onClick={() => setOpen(false)}
            disabled={isDeploying}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleDeploy} 
            disabled={isDeploying || !connectedAddress}
          >
            {isPending ? (
              <>
                <Loader2 className="mr-2 size-4 animate-spin" />
                Confirm in Wallet...
              </>
            ) : isConfirming ? (
              <>
                <Loader2 className="mr-2 size-4 animate-spin" />
                Deploying...
              </>
            ) : (
              <>
                <Rocket className="mr-2 size-4" />
                Deploy
              </>
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

export function EigenProviderOperatorManagement({ contract }: EigenProviderOperatorManagementProps) {
  const navigate = useNavigate()
  const { contracts, addContract } = useContracts()
  const [refreshKey, setRefreshKey] = useState(0)

  const eigenSupported = isEigenLayerSupported(contract.chainId)

  // Filter EigenOperatorProxy contracts on the same chain
  const operatorProxies = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === contract.chainId && c.type === "EigenOperatorProxy"
    )
  }, [contracts, contract.chainId, refreshKey])

  const handleDeploySuccess = (address: string, name: string) => {
    // Add the newly deployed contract to storage
    addContract({
      name,
      address: address as `0x${string}`,
      type: "EigenOperatorProxy",
      chainId: contract.chainId,
    })
    // Force refresh
    setRefreshKey((k) => k + 1)
  }

  if (!eigenSupported) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Manage Operators</CardTitle>
          <CardDescription>
            EigenLayer is not supported on this chain
          </CardDescription>
        </CardHeader>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Users className="size-5" />
              Manage Operators
            </CardTitle>
            <CardDescription>
              View and deploy EigenOperatorProxy contracts
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setRefreshKey((k) => k + 1)}
          >
            <RefreshCw className="mr-2 size-4" />
            Refresh
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Deploy section */}
        <div className="rounded-lg border p-4 bg-muted/30">
          <div className="flex items-start justify-between gap-4">
            <div className="space-y-1">
              <h4 className="text-sm font-medium">Deploy New Operator Proxy</h4>
              <p className="text-xs text-muted-foreground">
                Create a new EigenOperatorProxy contract. You will be set as the handler 
                and can register it with coverage agents.
              </p>
            </div>
            <WalletRequirement requiredChainId={contract.chainId}>
              <DeployOperatorProxyDialog 
                chainId={contract.chainId} 
                onSuccess={handleDeploySuccess}
              />
            </WalletRequirement>
          </div>
        </div>

        <Separator />

        {/* List of existing operator proxies */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium">
              Saved Operator Proxies ({operatorProxies.length})
            </h4>
          </div>

          {operatorProxies.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              <Users className="mx-auto mb-2 size-8 opacity-50" />
              <p>No operator proxies saved on this chain</p>
              <p className="mt-1 text-xs">
                Deploy a new one or add an existing one from the Add Contract page
              </p>
            </div>
          ) : (
            <ScrollArea className="h-fit max-h-[400px]">
              <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
                {operatorProxies.map((proxy) => (
                  <div key={proxy.id} className="relative group">
                    <ContractCard contract={proxy} />
                    <Button
                      size="sm"
                      variant="secondary"
                      className="absolute bottom-3 right-3 opacity-0 group-hover:opacity-100 transition-opacity"
                      onClick={() => navigate(`/interact/${proxy.id}`)}
                    >
                      <ExternalLink className="mr-1 size-3" />
                      Manage
                    </Button>
                  </div>
                ))}
              </div>
            </ScrollArea>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
