import { useMemo, useState, useEffect } from "react"
import {
    RefreshCw,
    Loader2,
    User,
    Plus,
    Trash2,
    Settings,
    UserPlus,
    Layers,
    Shield,
    Key,
    Coins,
    ArrowRight,
    CheckCircle,
    AlertCircle,
} from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from "wagmi"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iEigenOperatorProxyAbi, iEigenServiceManagerAbi } from "@/generated/abis"
import {
    iPermissionControllerAbi,
    iAllocationManagerAbi,
    iDelegationManagerAbi,
    iStrategyManagerAbi,
    iStrategyAbi,
    ierc20Abi,
} from "@/generated/eigen-abis"
import { supportedChains } from "@/lib/wagmi"
import { WalletRequirement } from "@/components/WalletRequirement"
import { ContractCard } from "@/components/ContractCard"
import { CoverageProviderSelect, CoverageAgentSelect } from "@/components/ContractSelects"
import {
    useAvailableCoverageProviders,
    useChainFilteredContracts,
    getSelectedProvider,
    getSelectedCoverageAgent,
} from "@/hooks/use-chain-filtered-contracts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
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
import { CopyableAddress } from "@/components/ui/copyable-address"

// EigenAddresses type matching the contract struct
interface EigenAddresses {
    allocationManager: `0x${string}`
    delegationManager: `0x${string}`
    strategyManager: `0x${string}`
    rewardsCoordinator: `0x${string}`
    permissionController: `0x${string}`
}

interface EigenOperatorProxyManagementProps {
    contract: CoverageContract
}

interface StrategyAllocation {
    address: string
    magnitude: number // Stored as percentage (0-100)
}

type SupportedChainId = (typeof supportedChains)[number]["id"]

// Pending Admin Card Component
function PendingAdminCard({
    contract,
    chainId,
    eigenAddresses,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    eigenAddresses: EigenAddresses | undefined
}) {
    const { address: connectedAddress } = useAccount()

    const {
        data: pendingAdmins,
        isLoading: isLoadingPending,
        refetch: refetchPending,
    } = useReadContract({
        address: eigenAddresses?.permissionController,
        abi: iPermissionControllerAbi,
        functionName: "getPendingAdmins",
        args: [contract.address],
        chainId,
        query: {
            enabled: !!eigenAddresses && !!chainId,
        },
    })

    const {
        data: admins,
        isLoading: isLoadingAdmins,
        refetch: refetchAdmins,
    } = useReadContract({
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

        writeContract(
            {
                address: eigenAddresses.permissionController,
                abi: iPermissionControllerAbi,
                functionName: "acceptAdmin",
                args: [contract.address],
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
                        onClick={() => {
                            refetchPending()
                            refetchAdmins()
                        }}
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
                                        <div
                                            key={admin}
                                            className="flex items-center gap-2 p-2 rounded-lg border bg-green-500/5 border-green-500/20"
                                        >
                                            <CheckCircle className="size-4 text-green-500" />
                                            <span className="font-mono text-sm truncate flex-1">
                                                {admin}
                                            </span>
                                            {connectedAddress?.toLowerCase() ===
                                                admin.toLowerCase() && (
                                                <Badge variant="secondary" className="text-xs">
                                                    You
                                                </Badge>
                                            )}
                                        </div>
                                    ))
                                ) : (
                                    <p className="text-sm text-muted-foreground">
                                        No active admins
                                    </p>
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
                                        <div
                                            key={admin}
                                            className="flex items-center gap-2 p-2 rounded-lg border bg-yellow-500/5 border-yellow-500/20"
                                        >
                                            <span className="font-mono text-sm truncate flex-1">
                                                {admin}
                                            </span>
                                            {connectedAddress?.toLowerCase() ===
                                                admin.toLowerCase() && (
                                                <Badge
                                                    variant="outline"
                                                    className="text-xs border-yellow-500/50 text-yellow-600"
                                                >
                                                    Pending for you
                                                </Badge>
                                            )}
                                        </div>
                                    ))
                                ) : (
                                    <p className="text-sm text-muted-foreground">
                                        No pending admin requests
                                    </p>
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
                                            <h4 className="text-sm font-medium">
                                                Admin Request Pending
                                            </h4>
                                            <p className="text-xs text-muted-foreground mt-1">
                                                You have a pending admin request for this operator
                                                proxy. Accept to gain admin permissions.
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
    eigenAddresses,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    eigenAddresses: EigenAddresses | undefined
}) {
    // Get registered operator sets
    const {
        data: registeredSets,
        isLoading: isLoadingSets,
        refetch: refetchSets,
    } = useReadContract({
        address: eigenAddresses?.allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getRegisteredSets",
        args: [contract.address],
        chainId,
        query: {
            enabled: !!eigenAddresses && !!chainId,
        },
    })

    // Get allocation delay
    const {
        data: allocationDelay,
        isLoading: isLoadingDelay,
        refetch: refetchDelay,
    } = useReadContract({
        address: eigenAddresses?.allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getAllocationDelay",
        args: [contract.address],
        chainId,
        query: {
            enabled: !!eigenAddresses && !!chainId,
        },
    })

    const isLoading = isLoadingSets || isLoadingDelay

    const refetch = () => {
        refetchSets()
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
                    <Button variant="outline" size="sm" onClick={refetch} disabled={isLoading}>
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
                                    {allocationDelay[0]
                                        ? `${allocationDelay[1]} blocks`
                                        : "Not set"}
                                </Badge>
                            </div>
                        )}

                        {/* Registered Operator Sets */}
                        <div className="space-y-3">
                            <Label className="text-sm font-medium flex items-center gap-2">
                                <Shield className="size-4 text-blue-500" />
                                Registered Operator Sets ({registeredSets?.length ?? 0})
                            </Label>
                            {registeredSets && registeredSets.length > 0 ? (
                                <div className="grid gap-4">
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
                                    No registered operator sets. Register with a coverage agent to
                                    start receiving allocations.
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
    eigenAddresses: EigenAddresses | undefined
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
        <div className="rounded-lg border p-4 space-y-3">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <div className="size-8 rounded-full bg-blue-500/10 flex items-center justify-center">
                        <Layers className="size-4 text-blue-500" />
                    </div>
                    <div>
                        <p className="text-sm font-medium">Operator Set #{operatorSet.id}</p>
                        <div className="flex items-center gap-1 text-xs text-muted-foreground">
                            <span>AVS:</span>
                            <CopyableAddress
                                address={operatorSet.avs}
                                truncateChars={6}
                                variant="inline"
                                size="sm"
                            />
                        </div>
                    </div>
                </div>
                <Badge variant="secondary" className="text-xs">
                    {allocatedStrategies?.length ?? 0} / {strategies?.length ?? 0} allocated
                </Badge>
            </div>

            {allocatedStrategies && allocatedStrategies.length > 0 && (
                <div className="space-y-2 pt-3 border-t">
                    <p className="text-xs font-medium text-muted-foreground">
                        Allocated Strategies
                    </p>
                    <div className="grid gap-2">
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

// Strategy allocation row with magnitude, token info
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
    eigenAddresses: EigenAddresses | undefined
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

    // Get strategy underlying token
    const { data: underlyingToken } = useReadContract({
        address: strategy,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    // Get token symbol
    const { data: tokenSymbol } = useReadContract({
        address: underlyingToken as `0x${string}`,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    const formatMagnitude = (magnitude: bigint) => {
        const percentage = Number(magnitude) / 1e16
        return percentage.toFixed(2) + "%"
    }

    return (
        <div className="rounded-lg border bg-card p-3 space-y-2">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <Coins className="size-4 text-primary" />
                    <span className="font-medium">{tokenSymbol || "Loading..."}</span>
                </div>
                {allocation && (
                    <Badge variant="secondary" className="font-mono">
                        {formatMagnitude(allocation.currentMagnitude)}
                    </Badge>
                )}
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                    <p className="text-muted-foreground mb-0.5">Strategy</p>
                    <CopyableAddress
                        address={strategy}
                        truncateChars={6}
                        variant="inline"
                        size="sm"
                    />
                </div>
                <div>
                    <p className="text-muted-foreground mb-0.5">Underlying Token</p>
                    {underlyingToken ? (
                        <CopyableAddress
                            address={underlyingToken}
                            truncateChars={6}
                            variant="inline"
                            size="sm"
                        />
                    ) : (
                        <span className="text-muted-foreground">Loading...</span>
                    )}
                </div>
            </div>
        </div>
    )
}

// Hook to query whitelisted strategies from a service manager
function useWhitelistedStrategies(
    serviceManagerAddress: string | undefined,
    chainId: SupportedChainId | undefined
) {
    const {
        data: strategies,
        isLoading,
        refetch,
    } = useReadContract({
        address: serviceManagerAddress as `0x${string}`,
        abi: iEigenServiceManagerAbi,
        functionName: "whitelistedStrategies",
        chainId,
        query: {
            enabled: !!serviceManagerAddress && !!chainId,
        },
    })

    return { strategies: strategies as `0x${string}`[] | undefined, isLoading, refetch }
}

// Strategy Select Item that displays strategy address and underlying token symbol
function StrategySelectItem({
    address,
    chainId,
}: {
    address: `0x${string}`
    chainId: SupportedChainId | undefined
}) {
    // Get strategy underlying token
    const { data: underlyingToken } = useReadContract({
        address,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    // Get token symbol
    const { data: tokenSymbol } = useReadContract({
        address: underlyingToken as `0x${string}`,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    return (
        <SelectItem value={address} className="font-mono">
            <div className="flex flex-col gap-0.5 items-start">
                <div className="font-sans font-medium">{tokenSymbol || "Loading..."}</div>
                <div className="text-xs text-muted-foreground">
                    {address.slice(0, 10)}...{address.slice(-8)}
                </div>
            </div>
        </SelectItem>
    )
}

// Reusable Strategy Select component for selecting whitelisted strategies from a service manager
interface StrategySelectProps {
    value: string
    onValueChange: (value: string) => void
    serviceManagerAddress: string | undefined
    chainId: SupportedChainId | undefined
    placeholder?: string
    disabled?: boolean
}

function StrategySelect({
    value,
    onValueChange,
    serviceManagerAddress,
    chainId,
    placeholder,
    disabled,
}: StrategySelectProps) {
    const { strategies: whitelistedStrategies, isLoading: isLoadingStrategies } =
        useWhitelistedStrategies(serviceManagerAddress, chainId)

    return (
        <Select
            value={value}
            onValueChange={onValueChange}
            disabled={disabled || !serviceManagerAddress || isLoadingStrategies}
        >
            <SelectTrigger className="font-mono">
                <SelectValue
                    placeholder={
                        !serviceManagerAddress
                            ? "Select a service manager first..."
                            : isLoadingStrategies
                              ? "Loading strategies..."
                              : placeholder || "Select strategy..."
                    }
                />
            </SelectTrigger>
            <SelectContent>
                {!whitelistedStrategies || whitelistedStrategies.length === 0 ? (
                    <div className="px-2 py-4 text-center text-sm text-muted-foreground">
                        No whitelisted strategies found
                    </div>
                ) : (
                    whitelistedStrategies.map((address) => (
                        <StrategySelectItem key={address} address={address} chainId={chainId} />
                    ))
                )}
            </SelectContent>
        </Select>
    )
}

// Deposit Item Component - displays individual deposit with strategy details
function DepositItem({
    strategyAddress,
    shares,
    chainId,
}: {
    strategyAddress: `0x${string}`
    shares: bigint
    chainId: SupportedChainId | undefined
}) {
    // Get strategy underlying token
    const { data: underlyingToken } = useReadContract({
        address: strategyAddress,
        abi: iStrategyAbi,
        functionName: "underlyingToken",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    // Get token symbol
    const { data: tokenSymbol } = useReadContract({
        address: underlyingToken as `0x${string}`,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    // Get token decimals
    const { data: tokenDecimals } = useReadContract({
        address: underlyingToken as `0x${string}`,
        abi: ierc20Abi,
        functionName: "decimals",
        chainId,
        query: {
            enabled: !!underlyingToken && !!chainId,
        },
    })

    const formatShares = (value: bigint, decimals: number | undefined) => {
        const dec = decimals ?? 18
        return (Number(value) / 10 ** dec).toFixed(6)
    }

    return (
        <div className="rounded-lg border bg-card p-4 space-y-3">
            <div className="flex items-center justify-between">
                <span className="text-sm font-medium flex items-center gap-2">
                    <Coins className="size-4 text-primary" />
                    {tokenSymbol || "Loading..."}
                </span>
                <Badge variant="outline" className="font-mono">
                    {formatShares(shares, tokenDecimals)} shares
                </Badge>
            </div>

            <div className="grid grid-cols-2 gap-3 text-xs">
                <div className="space-y-1">
                    <p className="text-muted-foreground">Strategy Address</p>
                    <CopyableAddress
                        address={strategyAddress}
                        truncateChars={6}
                        variant="inline"
                        size="sm"
                    />
                </div>
                <div className="space-y-1">
                    <p className="text-muted-foreground">Underlying Token</p>
                    {underlyingToken ? (
                        <CopyableAddress
                            address={underlyingToken}
                            truncateChars={6}
                            variant="inline"
                            size="sm"
                        />
                    ) : (
                        <span className="text-muted-foreground">Loading...</span>
                    )}
                </div>
            </div>
        </div>
    )
}

// Staking Card Component - for delegating to operator and depositing into strategies
function StakingCard({
    contract,
    chainId,
    eigenAddresses,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    eigenAddresses: EigenAddresses | undefined
}) {
    const { address: connectedAddress } = useAccount()
    const [selectedServiceManagerId, setSelectedServiceManagerId] = useState<string>("")
    const [selectedStrategy, setSelectedStrategy] = useState<string>("")
    const [depositAmount, setDepositAmount] = useState<string>("")

    // Get available providers for this chain
    const { availableProviders } = useAvailableCoverageProviders(contract.chainId, [])

    // Get selected provider contract
    const selectedServiceManager = getSelectedProvider(selectedServiceManagerId, availableProviders)

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

    const {
        writeContract: writeDelegation,
        isPending: isDelegating,
        data: delegateHash,
    } = useWriteContract()
    const { isLoading: isDelegateConfirming, isSuccess: isDelegateSuccess } =
        useWaitForTransactionReceipt({
            hash: delegateHash,
        })

    const {
        writeContract: writeApprove,
        isPending: isApproving,
        data: approveHash,
    } = useWriteContract()
    const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } =
        useWaitForTransactionReceipt({
            hash: approveHash,
        })

    const {
        writeContract: writeDeposit,
        isPending: isDepositing,
        data: depositHash,
    } = useWriteContract()
    const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } =
        useWaitForTransactionReceipt({
            hash: depositHash,
        })

    useEffect(() => {
        if (isDelegateSuccess || isDepositSuccess || isApproveSuccess) {
            refetchDelegated()
            refetchDelegatedTo()
            refetchDeposits()
            refetchBalance()
            refetchAllowance()
        }
    }, [
        isDelegateSuccess,
        isDepositSuccess,
        isApproveSuccess,
        refetchDelegated,
        refetchDelegatedTo,
        refetchDeposits,
        refetchBalance,
        refetchAllowance,
    ])

    const handleDelegate = () => {
        if (!eigenAddresses) return

        writeDelegation(
            {
                address: eigenAddresses.delegationManager,
                abi: iDelegationManagerAbi,
                functionName: "delegateTo",
                args: [
                    contract.address,
                    { signature: "0x" as `0x${string}`, expiry: BigInt(0) },
                    "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
                ],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Delegation transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    const handleApprove = () => {
        if (!underlyingToken || !eigenAddresses || !depositAmount) return

        const decimals = tokenDecimals ?? 18
        const amountWei = BigInt(Math.floor(parseFloat(depositAmount) * 10 ** decimals))

        writeApprove(
            {
                address: underlyingToken as `0x${string}`,
                abi: ierc20Abi,
                functionName: "approve",
                args: [eigenAddresses.strategyManager, amountWei],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Approval transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    const handleDeposit = () => {
        if (!eigenAddresses || !selectedStrategy || !underlyingToken || !depositAmount) return

        const decimals = tokenDecimals ?? 18
        const amountWei = BigInt(Math.floor(parseFloat(depositAmount) * 10 ** decimals))

        writeDeposit(
            {
                address: eigenAddresses.strategyManager,
                abi: iStrategyManagerAbi,
                functionName: "depositIntoStrategy",
                args: [
                    selectedStrategy as `0x${string}`,
                    underlyingToken as `0x${string}`,
                    amountWei,
                ],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Deposit transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    const formatBalance = (balance: bigint | undefined, decimals: number | undefined) => {
        if (!balance) return "0"
        const dec = decimals ?? 18
        return (Number(balance) / 10 ** dec).toFixed(6)
    }

    const needsApproval = useMemo(() => {
        // Check if we have the necessary data to calculate
        if (tokenAllowance === undefined || !depositAmount || tokenDecimals === undefined)
            return false

        const parsedAmount = parseFloat(depositAmount)
        if (isNaN(parsedAmount) || parsedAmount <= 0) return false

        const decimals = tokenDecimals ?? 18
        const amountWei = BigInt(Math.floor(parsedAmount * 10 ** decimals))

        // Need approval if deposit amount exceeds current allowance
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
                                    <Badge className="bg-green-500">
                                        Delegated to this operator
                                    </Badge>
                                ) : (
                                    <Badge variant="secondary">Delegated to another operator</Badge>
                                )
                            ) : (
                                <Badge variant="outline">Not delegated</Badge>
                            )}
                        </div>

                        {isDelegated && delegatedTo && !isDelegatedToThis && (
                            <div className="text-xs text-muted-foreground">
                                Currently delegated to:{" "}
                                <span className="font-mono">
                                    {delegatedTo.slice(0, 10)}...{delegatedTo.slice(-8)}
                                </span>
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
                                Deposit tokens into an EigenLayer strategy. Your deposit will be
                                delegated to the operator you're delegated to.
                            </p>
                        </div>

                        <div className="space-y-2">
                            <Label>Service Manager</Label>
                            <CoverageProviderSelect
                                selectedContractId={selectedServiceManagerId}
                                onSelectedContractIdChange={(value) => {
                                    setSelectedServiceManagerId(value)
                                    setSelectedStrategy("") // Reset strategy when service manager changes
                                }}
                                contracts={availableProviders}
                            />
                            <p className="text-xs text-muted-foreground">
                                Select a service manager to see available strategies
                            </p>
                        </div>

                        {/* Coverage Provider Quick Actions */}
                        {selectedServiceManager && (
                            <div className="max-w-sm">
                                <ContractCard
                                    contract={{
                                        id: selectedServiceManager.id,
                                        address: selectedServiceManager.address as `0x${string}`,
                                        name: selectedServiceManager.name,
                                        type: "CoverageProvider",
                                        chainId: contract.chainId,
                                        additionalFields: {
                                            providerType: "EigenLayer",
                                        },
                                    }}
                                />
                            </div>
                        )}

                        <div className="space-y-2">
                            <Label>Strategy</Label>
                            <StrategySelect
                                value={selectedStrategy}
                                onValueChange={setSelectedStrategy}
                                serviceManagerAddress={selectedServiceManager?.address}
                                chainId={chainId}
                            />
                        </div>

                        {selectedStrategy && underlyingToken && (
                            <>
                                <div className="space-y-2">
                                    <div className="flex items-center justify-between">
                                        <Label>Amount</Label>
                                        <span className="text-xs text-muted-foreground">
                                            Balance: {formatBalance(tokenBalance, tokenDecimals)}{" "}
                                            {tokenSymbol}
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
                                        disabled={
                                            isApproving || isApproveConfirming || !depositAmount
                                        }
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
                                        disabled={
                                            isDepositing || isDepositConfirming || !depositAmount
                                        }
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
                            <div className="space-y-3">
                                <div className="rounded-lg bg-muted/50 p-3">
                                    <h4 className="text-sm font-medium">Your Current Deposits</h4>
                                    <p className="text-xs text-muted-foreground mt-1">
                                        View your deposited strategies with underlying token
                                        details.
                                    </p>
                                </div>
                                <div className="space-y-3">
                                    {deposits[0].map((strategy, index) => (
                                        <DepositItem
                                            key={strategy}
                                            strategyAddress={strategy}
                                            shares={deposits[1][index]}
                                            chainId={chainId}
                                        />
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

function RegisterCoverageAgentForm({
    contract,
    chainId,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
}) {
    const [serviceManagerId, setServiceManagerId] = useState("")
    const [coverageAgentId, setCoverageAgentId] = useState("")
    const [rewardsSplit, setRewardsSplit] = useState(0) // Stored as percentage (0-100)

    // Get available providers and coverage agents
    const { availableProviders } = useAvailableCoverageProviders(contract.chainId, [])
    const { coverageAgents } = useChainFilteredContracts(contract.chainId)

    // Look up selected contracts
    const selectedServiceManager = getSelectedProvider(serviceManagerId, availableProviders)
    const selectedCoverageAgent = getSelectedCoverageAgent(coverageAgentId, coverageAgents)

    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault()

        if (!selectedServiceManager || !selectedCoverageAgent) {
            toast.error("Please fill in all fields")
            return
        }

        // Convert percentage (0-100) to basis points (0-10000)
        const rewardsSplitBps = Math.floor(rewardsSplit * 100)

        writeContract(
            {
                address: contract.address,
                abi: iEigenOperatorProxyAbi,
                functionName: "registerCoverageAgent",
                args: [
                    selectedServiceManager.address as `0x${string}`,
                    selectedCoverageAgent.address as `0x${string}`,
                    rewardsSplitBps,
                ],
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
        <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
                <Label>Service Manager</Label>
                <CoverageProviderSelect
                    selectedContractId={serviceManagerId}
                    onSelectedContractIdChange={setServiceManagerId}
                    contracts={availableProviders}
                />
                <p className="text-xs text-muted-foreground">
                    The EigenLayer service manager contract address
                </p>
            </div>

            <div className="space-y-2">
                <Label>Coverage Agent</Label>
                <CoverageAgentSelect
                    selectedContractId={coverageAgentId}
                    onSelectedContractIdChange={setCoverageAgentId}
                    contracts={coverageAgents}
                />
                <p className="text-xs text-muted-foreground">
                    The coverage agent contract to register with
                </p>
            </div>

            <div className="space-y-2">
                <div className="flex items-center justify-between">
                    <Label>Rewards Split</Label>
                    <span className="text-sm font-medium tabular-nums">{rewardsSplit}%</span>
                </div>
                <Slider
                    value={[rewardsSplit]}
                    onValueChange={(values) => setRewardsSplit(values[0])}
                    min={0}
                    max={100}
                    step={1}
                />
                <p className="text-xs text-muted-foreground">
                    Percentage of rewards kept by operator (0% = all to restakers, 100% = all to
                    operator)
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

function AllocateForm({
    contract,
    chainId,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
}) {
    const [serviceManagerId, setServiceManagerId] = useState("")
    const [coverageAgentId, setCoverageAgentId] = useState("")
    const [strategies, setStrategies] = useState<StrategyAllocation[]>([
        { address: "", magnitude: 0 },
    ])

    // Get available providers and coverage agents
    const { availableProviders } = useAvailableCoverageProviders(contract.chainId, [])
    const { coverageAgents } = useChainFilteredContracts(contract.chainId)

    // Look up selected contracts
    const selectedServiceManager = getSelectedProvider(serviceManagerId, availableProviders)
    const selectedCoverageAgent = getSelectedCoverageAgent(coverageAgentId, coverageAgents)

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

        if (!selectedServiceManager || !selectedCoverageAgent) {
            toast.error("Please fill in service manager and coverage agent")
            return
        }

        const validStrategies = strategies.filter((s) => s.address && s.magnitude > 0)
        if (validStrategies.length === 0) {
            toast.error("Please add at least one strategy allocation with magnitude > 0")
            return
        }

        const strategyAddresses = validStrategies.map((s) => s.address as `0x${string}`)
        const magnitudes = validStrategies.map((s) => percentageToWad(s.magnitude))

        writeContract(
            {
                address: contract.address,
                abi: iEigenOperatorProxyAbi,
                functionName: "allocate",
                args: [
                    selectedServiceManager.address as `0x${string}`,
                    selectedCoverageAgent.address as `0x${string}`,
                    strategyAddresses,
                    magnitudes,
                ],
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
        <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
                <Label>Service Manager</Label>
                <CoverageProviderSelect
                    selectedContractId={serviceManagerId}
                    onSelectedContractIdChange={setServiceManagerId}
                    contracts={availableProviders}
                />
            </div>

            <div className="space-y-2">
                <Label>Coverage Agent</Label>
                <CoverageAgentSelect
                    selectedContractId={coverageAgentId}
                    onSelectedContractIdChange={setCoverageAgentId}
                    contracts={coverageAgents}
                />
            </div>

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
                        <div
                            key={index}
                            className="flex gap-2 items-start p-3 rounded-lg border bg-muted/30"
                        >
                            <div className="flex-1 space-y-3">
                                <StrategySelect
                                    value={strategy.address}
                                    onValueChange={(value) => updateStrategyAddress(index, value)}
                                    serviceManagerAddress={selectedServiceManager?.address}
                                    chainId={chainId}
                                    placeholder="Select strategy..."
                                />
                                <div className="space-y-2">
                                    <div className="flex items-center justify-between">
                                        <span className="text-xs text-muted-foreground">
                                            Allocation
                                        </span>
                                        <span className="text-sm font-medium tabular-nums">
                                            {strategy.magnitude}%
                                        </span>
                                    </div>
                                    <Slider
                                        value={[strategy.magnitude]}
                                        onValueChange={(values) =>
                                            updateStrategyMagnitude(index, values[0])
                                        }
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
                <p className="text-sm text-green-600 text-center">Allocation successful!</p>
            )}
        </form>
    )
}

function UpdateMetadataForm({
    contract,
    chainId,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
}) {
    const [metadataUri, setMetadataUri] = useState("")

    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault()

        if (!metadataUri) {
            toast.error("Please enter a metadata URI")
            return
        }

        writeContract(
            {
                address: contract.address,
                abi: iEigenOperatorProxyAbi,
                functionName: "updateOperatorMetadataURI",
                args: [metadataUri],
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
                    A URL pointing to a JSON file containing operator metadata (name, description,
                    logo, etc.)
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
                <p className="text-sm text-green-600 text-center">Metadata updated successfully!</p>
            )}
        </form>
    )
}

export function EigenOperatorProxyManagement({ contract }: EigenOperatorProxyManagementProps) {
    const isChainSupported = supportedChains.some((chain) => chain.id === contract.chainId)

    const chainId = isChainSupported
        ? (contract.chainId as (typeof supportedChains)[number]["id"])
        : undefined

    // Query eigenAddresses from the EigenOperatorProxy contract
    const { data: eigenAddressesData } = useReadContract({
        address: contract.address,
        abi: iEigenOperatorProxyAbi,
        functionName: "eigenAddresses",
        chainId,
        query: {
            enabled: isChainSupported,
        },
    })

    const eigenAddresses = eigenAddressesData as EigenAddresses | undefined

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
            {/* Staking Management Section */}
            <h2 className="text-lg font-semibold">Staking Management</h2>

            {/* Staking Card */}
            {eigenAddresses && (
                <StakingCard
                    contract={contract}
                    chainId={chainId}
                    eigenAddresses={eigenAddresses}
                />
            )}

            <Separator className="my-6" />

            {/* Operator Management Section */}
            <h2 className="text-lg font-semibold">Operator Management</h2>

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
                                        <h4 className="text-sm font-medium">
                                            Register Coverage Agent
                                        </h4>
                                        <p className="text-xs text-muted-foreground mt-1">
                                            Register this operator to provide coverage for a
                                            specific coverage agent through an EigenLayer service
                                            manager.
                                        </p>
                                    </div>
                                    <RegisterCoverageAgentForm
                                        contract={contract}
                                        chainId={chainId}
                                    />
                                </div>
                            </TabsContent>

                            <TabsContent value="allocate" className="mt-4">
                                <div className="space-y-4">
                                    <div className="rounded-lg bg-muted/50 p-3">
                                        <h4 className="text-sm font-medium">
                                            Allocate to Strategies
                                        </h4>
                                        <p className="text-xs text-muted-foreground mt-1">
                                            Allocate stake to strategies for a coverage agent. This
                                            can only be called after the allocation delay period
                                            (~17.5 days).
                                        </p>
                                    </div>
                                    <AllocateForm contract={contract} chainId={chainId} />
                                </div>
                            </TabsContent>

                            <TabsContent value="metadata" className="mt-4">
                                <div className="space-y-4">
                                    <div className="rounded-lg bg-muted/50 p-3">
                                        <h4 className="text-sm font-medium">
                                            Update Operator Metadata
                                        </h4>
                                        <p className="text-xs text-muted-foreground mt-1">
                                            Update the metadata URI for this operator. The URI
                                            should point to a JSON file containing operator
                                            information.
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
