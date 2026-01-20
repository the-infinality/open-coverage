import { useState, useEffect, useRef } from "react"
import { type Address, encodeDeployData, getContractAddress } from "viem"
import {
    useAccount,
    useSendTransaction,
    useWaitForTransactionReceipt,
    useReadContract,
} from "wagmi"
import { toast } from "sonner"
import { Users, Plus, Loader2, CheckCircle2 } from "lucide-react"
import type { CoverageContract } from "@/types/contracts"
import { useContracts } from "@/hooks/use-contracts"
import { useChainFilteredContracts } from "@/hooks/use-chain-filtered-contracts"
import { supportedChains } from "@/lib/wagmi"
import {
    eigenOperatorProxyDeployAbi,
    eigenOperatorProxyBytecode,
} from "@/generated/eigen-operator-proxy-deployment"
import { iEigenServiceManagerAbi } from "@/generated/abis"
import { WalletRequirement } from "@/components/WalletRequirement"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { ScrollArea } from "@/components/ui/scroll-area"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from "@/components/ui/dialog"
import { generateContractName } from "@/lib/utils"
import { ContractCard } from "@/components/ContractCard"

type SupportedChainId = (typeof supportedChains)[number]["id"]

interface OperatorProxiesManagementProps {
    contract: CoverageContract
}

/**
 * Item displaying a single EigenOperatorProxy contract
 */
function OperatorProxyItem({ operatorProxy }: { operatorProxy: CoverageContract }) {
    return <ContractCard contract={operatorProxy} />
}

// Type for EigenAddresses struct
interface EigenAddresses {
    allocationManager: Address
    delegationManager: Address
    strategyManager: Address
    rewardsCoordinator: Address
    permissionController: Address
}

/**
 * Form to deploy a new EigenOperatorProxy
 */
function DeployOperatorProxyForm({
    chainId,
    eigenAddresses,
    onSuccess,
    onClose,
}: {
    chainId: number
    eigenAddresses: EigenAddresses
    onSuccess: (address: Address, name: string) => void
    onClose: () => void
}) {
    const { operatorProxies } = useChainFilteredContracts(chainId)
    const { address: connectedAddress } = useAccount()
    const [operatorName, setOperatorName] = useState(
        generateContractName("EigenOperatorProxy", operatorProxies)
    )
    const [handlerAddress, setHandlerAddress] = useState(connectedAddress)
    const [metadataUri, setMetadataUri] = useState("https://coverage.example.com/operator.json")

    const successHandledRef = useRef(false)

    const { mutate, isPending, data: hash } = useSendTransaction()
    const {
        isLoading: isConfirming,
        isSuccess,
        data: receipt,
    } = useWaitForTransactionReceipt({ hash })

    // Compute the deployed address from the receipt
    const deployedAddress = (() => {
        if (!isSuccess || !receipt) return null

        // Try to get contract address from receipt
        if (receipt.contractAddress) {
            return receipt.contractAddress
        }

        // If contractAddress is null, try to compute it from sender and nonce
        // This can happen with some RPC providers
        if (receipt.from) {
            try {
                // For contract creation, we need the nonce at time of deployment
                // The receipt doesn't directly give us this, but we can try to compute
                return getContractAddress({
                    from: receipt.from,
                    nonce: BigInt(receipt.transactionIndex),
                })
            } catch {
                return null
            }
        }

        return null
    })()

    // Handle side effects (toast, callback) when deployment succeeds
    useEffect(() => {
        if (isSuccess && receipt && !successHandledRef.current) {
            successHandledRef.current = true

            if (deployedAddress) {
                toast.success(`EigenOperatorProxy deployed at ${deployedAddress.slice(0, 10)}...`)
                onSuccess(
                    deployedAddress,
                    operatorName || `Operator Proxy ${deployedAddress.slice(0, 8)}`
                )
            } else {
                toast.error(
                    "Deployment succeeded but couldn't extract contract address from receipt"
                )
            }
        }
    }, [isSuccess, receipt, deployedAddress, onSuccess, operatorName])

    const handleDeploy = () => {
        if (!handlerAddress) {
            toast.error("Please enter a handler address")
            return
        }

        // Encode constructor arguments
        const deployData = encodeDeployData({
            abi: eigenOperatorProxyDeployAbi,
            bytecode: eigenOperatorProxyBytecode,
            args: [
                {
                    allocationManager: eigenAddresses.allocationManager,
                    delegationManager: eigenAddresses.delegationManager,
                    strategyManager: eigenAddresses.strategyManager,
                    rewardsCoordinator: eigenAddresses.rewardsCoordinator,
                    permissionController: eigenAddresses.permissionController,
                },
                handlerAddress as Address,
                metadataUri,
            ],
        })

        mutate(
            {
                data: deployData,
                chainId: chainId as SupportedChainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Deployment transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    if (deployedAddress) {
        return (
            <div className="space-y-4">
                <div className="rounded-lg bg-green-500/10 border border-green-500/30 p-4 space-y-3">
                    <div className="flex items-center gap-2">
                        <CheckCircle2 className="size-5 text-green-500" />
                        <h4 className="font-medium text-green-700">Deployment Successful!</h4>
                    </div>
                    <p className="text-sm text-muted-foreground">
                        Your EigenOperatorProxy has been deployed and saved.
                    </p>
                    <div className="flex items-center gap-2">
                        <span className="text-sm text-muted-foreground">Contract:</span>
                        <CopyableAddress address={deployedAddress} />
                    </div>
                </div>
                <Button onClick={onClose} className="w-full">
                    Close
                </Button>
            </div>
        )
    }

    return (
        <div className="space-y-4">
            <div className="rounded-lg bg-muted/50 p-3">
                <h4 className="text-sm font-medium">Deployment Info</h4>
                <p className="text-xs text-muted-foreground mt-1">
                    This will deploy a new EigenOperatorProxy contract. The handler will have
                    administrative control over the operator proxy.
                </p>
            </div>

            <div className="space-y-2">
                <Label htmlFor="operator-name">Operator Name (for reference)</Label>
                <Input
                    id="operator-name"
                    placeholder="My Operator Proxy"
                    value={operatorName}
                    onChange={(e) => setOperatorName(e.target.value)}
                    disabled={isPending || isConfirming}
                />
                <p className="text-xs text-muted-foreground">
                    A friendly name to identify this operator proxy
                </p>
            </div>

            <div className="space-y-2">
                <Label htmlFor="handler-address">Handler Address</Label>
                <Input
                    id="handler-address"
                    placeholder="0x..."
                    value={handlerAddress}
                    onChange={(e) => setHandlerAddress(e.target.value as Address)}
                    className="font-mono"
                    disabled={isPending || isConfirming}
                />
                <p className="text-xs text-muted-foreground">
                    The address that will manage this operator proxy (defaults to your wallet)
                </p>
            </div>

            <div className="space-y-2">
                <Label htmlFor="metadata-uri">Operator Metadata URI</Label>
                <Input
                    id="metadata-uri"
                    placeholder="https://example.com/operator.json"
                    value={metadataUri}
                    onChange={(e) => setMetadataUri(e.target.value)}
                    disabled={isPending || isConfirming}
                />
                <p className="text-xs text-muted-foreground">
                    A URL pointing to JSON metadata for this operator
                </p>
            </div>

            <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
                <p className="text-xs font-medium text-muted-foreground">
                    EigenLayer Addresses (from provider contract)
                </p>
                <div className="grid gap-1 text-xs">
                    <div className="flex justify-between">
                        <span className="text-muted-foreground">Allocation Manager</span>
                        <span className="font-mono">
                            {eigenAddresses.allocationManager.slice(0, 10)}...
                        </span>
                    </div>
                    <div className="flex justify-between">
                        <span className="text-muted-foreground">Delegation Manager</span>
                        <span className="font-mono">
                            {eigenAddresses.delegationManager.slice(0, 10)}...
                        </span>
                    </div>
                    <div className="flex justify-between">
                        <span className="text-muted-foreground">Permission Controller</span>
                        <span className="font-mono">
                            {eigenAddresses.permissionController.slice(0, 10)}...
                        </span>
                    </div>
                </div>
            </div>

            <WalletRequirement requiredChainId={chainId}>
                <Button
                    onClick={handleDeploy}
                    disabled={isPending || isConfirming || !handlerAddress}
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
                            Deploying...
                        </>
                    ) : (
                        <>
                            <Plus className="mr-2 size-4" />
                            Deploy Operator Proxy
                        </>
                    )}
                </Button>
            </WalletRequirement>
        </div>
    )
}

/**
 * Component to manage EigenOperatorProxy contracts for a Coverage Provider
 */
export function OperatorProxiesManagement({ contract }: OperatorProxiesManagementProps) {
    const [isDeployDialogOpen, setIsDeployDialogOpen] = useState(false)
    const { addContract } = useContracts()
    const { operatorProxies } = useChainFilteredContracts(contract.chainId)

    const isChainSupported = supportedChains.some((chain) => chain.id === contract.chainId)
    const chainId = isChainSupported ? (contract.chainId as SupportedChainId) : undefined

    // Fetch eigenAddresses from the provider contract
    const { data: eigenAddresses, isLoading: isLoadingAddresses } = useReadContract({
        address: contract.address,
        abi: iEigenServiceManagerAbi,
        functionName: "eigenAddresses",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    const handleDeploySuccess = (address: Address, name: string) => {
        // Save the deployed contract
        addContract({
            name,
            address,
            type: "EigenOperatorProxy",
            chainId: contract.chainId,
        })
        // Close dialog after a short delay
        setTimeout(() => {
            setIsDeployDialogOpen(false)
        }, 2000)
    }

    // Show loading state while fetching eigenAddresses
    if (isLoadingAddresses) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Users className="size-5" />
                        Manage Operator Proxies
                    </CardTitle>
                    <CardDescription>Loading EigenLayer configuration...</CardDescription>
                </CardHeader>
                <CardContent className="flex items-center justify-center py-8">
                    <Loader2 className="size-6 animate-spin text-muted-foreground" />
                </CardContent>
            </Card>
        )
    }

    // Show error state if eigenAddresses couldn't be fetched
    if (!eigenAddresses) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Users className="size-5" />
                        Operator Proxies
                    </CardTitle>
                    <CardDescription>
                        Unable to fetch EigenLayer addresses from this contract
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
                            Manage Operator Proxies
                        </CardTitle>
                        <CardDescription>
                            View and deploy EigenOperatorProxy contracts for this chain
                        </CardDescription>
                    </div>
                    <Dialog open={isDeployDialogOpen} onOpenChange={setIsDeployDialogOpen}>
                        <DialogTrigger asChild>
                            <Button size="sm">
                                <Plus className="mr-2 size-4" />
                                Deploy New
                            </Button>
                        </DialogTrigger>
                        <DialogContent className="sm:max-w-[500px]">
                            <DialogHeader>
                                <DialogTitle>Deploy EigenOperatorProxy</DialogTitle>
                                <DialogDescription>
                                    Deploy a new EigenOperatorProxy contract to manage operator
                                    registration and allocations.
                                </DialogDescription>
                            </DialogHeader>
                            <DeployOperatorProxyForm
                                chainId={contract.chainId}
                                eigenAddresses={eigenAddresses}
                                onSuccess={handleDeploySuccess}
                                onClose={() => setIsDeployDialogOpen(false)}
                            />
                        </DialogContent>
                    </Dialog>
                </div>
            </CardHeader>
            <CardContent className="space-y-4">
                {/* Existing Operator Proxies */}
                <div className="flex items-center justify-between">
                    <div>
                        <h4 className="text-sm font-medium">Saved Operator Proxies</h4>
                        <p className="text-xs text-muted-foreground">
                            Operator proxies on this chain that you've saved
                        </p>
                    </div>
                    <Badge variant="secondary">{operatorProxies.length} saved</Badge>
                </div>

                {operatorProxies.length === 0 ? (
                    <div className="py-8 text-center space-y-3">
                        <div className="size-12 rounded-full bg-muted/50 flex items-center justify-center mx-auto">
                            <Users className="size-6 text-muted-foreground" />
                        </div>
                        <div className="space-y-1">
                            <p className="text-sm font-medium">No operator proxies</p>
                            <p className="text-xs text-muted-foreground">
                                Deploy a new operator proxy or add an existing one to get started
                            </p>
                        </div>
                    </div>
                ) : (
                    <ScrollArea className="h-fit">
                        <div className="flex flex-col gap-2 h-fit  max-h-[600px]">
                            {operatorProxies.map((op) => (
                                <OperatorProxyItem key={op.id} operatorProxy={op} />
                            ))}
                        </div>
                    </ScrollArea>
                )}

                <Separator />

                {/* Quick add section */}
                <div className="rounded-lg bg-muted/30 p-3 space-y-2">
                    <p className="text-xs font-medium">Already have an operator proxy?</p>
                    <p className="text-xs text-muted-foreground">
                        Add an existing EigenOperatorProxy contract from the main Contracts page to
                        manage it here.
                    </p>
                    <Button variant="outline" size="sm" asChild>
                        <a href="/add-contract" className="flex items-center gap-2">
                            <Plus className="size-3" />
                            Add Existing Contract
                        </a>
                    </Button>
                </div>
            </CardContent>
        </Card>
    )
}
