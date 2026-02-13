import { useState, useEffect, useRef, useMemo } from "react"
import { type Address, isAddress, BaseError } from "viem"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from "wagmi"
import { Loader2, CheckCircle2, User, DollarSign, Link as LinkIcon, Plus, Trash2 } from "lucide-react"
import { toast } from "sonner"
import { iEigenServiceManagerAbi } from "@/generated/abis"
import {
    iDelegationManagerAbi,
    iAllocationManagerAbi,
    iRewardsCoordinatorAbi,
} from "@/generated/eigen-abis"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"
import { Badge } from "@/components/ui/badge"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { CoverageAgentSelect } from "@/components/ContractSelects"
import { StrategySelect } from "@/components/StrategySelect"
import { useChainFilteredContracts } from "@/hooks/use-chain-filtered-contracts"
import { supportedChains } from "@/lib/wagmi"

type SupportedChainId = (typeof supportedChains)[number]["id"]

// Type for EigenAddresses struct (not used but matches contract)

/**
 * Decodes a contract error and returns a human-readable message
 */
function decodeContractError(error: unknown): string {
    if (error instanceof BaseError) {
        const errorMessage = error.message || ""
        const revertMatch = errorMessage.match(/reverted with reason string '([^']+)'/)
        if (revertMatch) return revertMatch[1]

        // Return shortMessage if available
        if (error.shortMessage) {
            return error.shortMessage
        }
    }

    const message = error instanceof Error ? error.message : String(error)
    return message.length > 200 ? message.slice(0, 200) + "..." : message
}

interface OperatorManagementProps {
    serviceManagerAddress: Address
    chainId: SupportedChainId | undefined
}

/**
 * Operator Management Component
 * Provides direct wallet-based operator management for EigenLayer operators
 */
export function OperatorManagement({ serviceManagerAddress, chainId }: OperatorManagementProps) {
    const { address: connectedAddress } = useAccount()
    const { coverageAgents } = useChainFilteredContracts(chainId as number)

    // State for register as operator
    const [metadataURI, setMetadataURI] = useState("")
    const [delegationApprover, setDelegationApprover] = useState<string>("")
    const [stakerOptOutWindowBlocks, setStakerOptOutWindowBlocks] = useState("0")

    // State for update metadata
    const [newMetadataURI, setNewMetadataURI] = useState("")

    // State for register to coverage agent
    const [selectedCoverageAgentId, setSelectedCoverageAgentId] = useState<string>("")

    // State for allocate
    const [allocateCoverageAgentId, setAllocateCoverageAgentId] = useState<string>("")
    const [allocateStrategies, setAllocateStrategies] = useState<Array<{ address: string; magnitude: number }>>([
        { address: "", magnitude: 0 },
    ])

    // State for set rewards split independently
    const [splitCoverageAgentId, setSplitCoverageAgentId] = useState<string>("")
    const [splitRewardsPercent, setSplitRewardsPercent] = useState(100)

    // Get selected coverage agent addresses from IDs
    const selectedCoverageAgent = coverageAgents.find((c) => c.id === selectedCoverageAgentId)
        ?.address
    const allocateCoverageAgent = coverageAgents.find((c) => c.id === allocateCoverageAgentId)
        ?.address
    const splitCoverageAgent = coverageAgents.find((c) => c.id === splitCoverageAgentId)?.address

    // Get EigenLayer contract addresses
    const { data: eigenAddresses } = useReadContract({
        address: serviceManagerAddress,
        abi: iEigenServiceManagerAbi,
        functionName: "eigenAddresses",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    // Check if connected wallet is an operator
    const { data: isOperator, refetch: refetchIsOperator } = useReadContract({
        address: eigenAddresses?.delegationManager,
        abi: iDelegationManagerAbi,
        functionName: "isOperator",
        args: connectedAddress ? [connectedAddress] : undefined,
        chainId,
        query: {
            enabled: !!eigenAddresses?.delegationManager && !!connectedAddress && !!chainId,
        },
    })

    // Get operator metadata URI if they are an operator
    const { data: currentMetadataURI } = useReadContract({
        address: eigenAddresses?.delegationManager,
        abi: iDelegationManagerAbi,
        functionName: "operatorMetadataURI",
        args: connectedAddress ? [connectedAddress] : undefined,
        chainId,
        query: {
            enabled:
                !!eigenAddresses?.delegationManager &&
                !!connectedAddress &&
                !!chainId &&
                !!isOperator,
        },
    })

    // Get registered operator sets
    const { data: registeredSets, refetch: refetchRegisteredSets } = useReadContract({
        address: eigenAddresses?.allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getRegisteredSets",
        args: connectedAddress ? [connectedAddress] : undefined,
        chainId,
        query: {
            enabled:
                !!eigenAddresses?.allocationManager &&
                !!connectedAddress &&
                !!chainId &&
                !!isOperator,
        },
    })

    // Get operator set ID for selected coverage agent (for registration)
    const { data: registerOperatorSetId } = useReadContract({
        address: serviceManagerAddress,
        abi: iEigenServiceManagerAbi,
        functionName: "getOperatorSetId",
        args:
            selectedCoverageAgent && isAddress(selectedCoverageAgent)
                ? [selectedCoverageAgent as Address]
                : undefined,
        chainId,
        query: {
            enabled:
                !!chainId && !!selectedCoverageAgent && isAddress(selectedCoverageAgent),
        },
    })

    // Get operator set ID for allocation coverage agent
    const { data: allocateOperatorSetId } = useReadContract({
        address: serviceManagerAddress,
        abi: iEigenServiceManagerAbi,
        functionName: "getOperatorSetId",
        args:
            allocateCoverageAgent && isAddress(allocateCoverageAgent)
                ? [allocateCoverageAgent as Address]
                : undefined,
        chainId,
        query: {
            enabled:
                !!chainId && !!allocateCoverageAgent && isAddress(allocateCoverageAgent),
        },
    })

    // Get operator set ID for rewards split
    const { data: splitOperatorSetId } = useReadContract({
        address: serviceManagerAddress,
        abi: iEigenServiceManagerAbi,
        functionName: "getOperatorSetId",
        args:
            splitCoverageAgent && isAddress(splitCoverageAgent)
                ? [splitCoverageAgent as Address]
                : undefined,
        chainId,
        query: {
            enabled: !!chainId && !!splitCoverageAgent && isAddress(splitCoverageAgent),
        },
    })

    // Strategy addresses for allocation (valid only) for fetching max magnitudes
    const allocateStrategyAddresses = useMemo(() => {
        return allocateStrategies
            .map((s) => s.address)
            .filter((addr): addr is Address => !!addr && isAddress(addr))
    }, [allocateStrategies])

    // Max magnitudes for allocation (one per strategy, same order as allocateStrategyAddresses)
    const { data: maxAllocationMagnitudes } = useReadContract({
        address: eigenAddresses?.allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getMaxMagnitudes",
        args:
            connectedAddress && allocateStrategyAddresses.length > 0
                ? [connectedAddress, allocateStrategyAddresses]
                : undefined,
        chainId,
        query: {
            enabled:
                !!eigenAddresses?.allocationManager &&
                !!connectedAddress &&
                allocateStrategyAddresses.length > 0 &&
                !!chainId,
        },
    })

    // Write contract hooks
    const {
        writeContract: writeRegisterOperator,
        isPending: isPendingRegister,
        data: hashRegister,
    } = useWriteContract()
    const {
        isLoading: isConfirmingRegister,
        isSuccess: isSuccessRegister,
        isError: isErrorRegister,
        error: errorRegister,
    } = useWaitForTransactionReceipt({ hash: hashRegister })

    const {
        writeContract: writeUpdateMetadata,
        isPending: isPendingUpdate,
        data: hashUpdate,
    } = useWriteContract()
    const {
        isLoading: isConfirmingUpdate,
        isSuccess: isSuccessUpdate,
        isError: isErrorUpdate,
        error: errorUpdate,
    } = useWaitForTransactionReceipt({ hash: hashUpdate })

    const {
        writeContract: writeRegisterCoverageAgent,
        isPending: isPendingRegisterAgent,
        data: hashRegisterAgent,
    } = useWriteContract()
    const {
        isLoading: isConfirmingRegisterAgent,
        isSuccess: isSuccessRegisterAgent,
        isError: isErrorRegisterAgent,
        error: errorRegisterAgent,
    } = useWaitForTransactionReceipt({ hash: hashRegisterAgent })

    const {
        writeContract: writeAllocate,
        isPending: isPendingAllocate,
        data: hashAllocate,
    } = useWriteContract()
    const {
        isLoading: isConfirmingAllocate,
        isSuccess: isSuccessAllocate,
        isError: isErrorAllocate,
        error: errorAllocate,
    } = useWaitForTransactionReceipt({ hash: hashAllocate })

    const {
        writeContract: writeSetRewardsSplitStandalone,
        isPending: isPendingSplitStandalone,
        data: hashSplitStandalone,
    } = useWriteContract()
    const {
        isLoading: isConfirmingSplitStandalone,
        isSuccess: isSuccessSplitStandalone,
        isError: isErrorSplitStandalone,
        error: errorSplitStandalone,
    } = useWaitForTransactionReceipt({ hash: hashSplitStandalone })

    // Track previous success states
    const prevSuccessRegisterRef = useRef(false)
    const prevSuccessUpdateRef = useRef(false)
    const prevSuccessRegisterAgentRef = useRef(false)
    const prevSuccessAllocateRef = useRef(false)
    const prevSuccessSplitStandaloneRef = useRef(false)

    const hasShownErrorRegister = useRef<string>("")
    const hasShownErrorUpdate = useRef<string>("")
    const hasShownErrorRegisterAgent = useRef<string>("")
    const hasShownErrorAllocate = useRef<string>("")
    const hasShownErrorSplitStandalone = useRef<string>("")

    // Handle successful operator registration
    useEffect(() => {
        if (isSuccessRegister && !prevSuccessRegisterRef.current) {
            refetchIsOperator()
            setMetadataURI("")
            setDelegationApprover("")
            setStakerOptOutWindowBlocks("0")
        }
        prevSuccessRegisterRef.current = isSuccessRegister
    }, [isSuccessRegister, refetchIsOperator])

    // Handle successful metadata update
    useEffect(() => {
        if (isSuccessUpdate && !prevSuccessUpdateRef.current) {
            setNewMetadataURI("")
        }
        prevSuccessUpdateRef.current = isSuccessUpdate
    }, [isSuccessUpdate])

    // Handle successful coverage agent registration
    useEffect(() => {
        if (isSuccessRegisterAgent && !prevSuccessRegisterAgentRef.current) {
            refetchRegisteredSets()
            setSelectedCoverageAgentId("")
        }
        prevSuccessRegisterAgentRef.current = isSuccessRegisterAgent
    }, [isSuccessRegisterAgent, refetchRegisteredSets])

    // Handle successful allocation
    useEffect(() => {
        if (isSuccessAllocate && !prevSuccessAllocateRef.current) {
            setAllocateCoverageAgentId("")
            setAllocateStrategies([{ address: "", magnitude: 0 }])
        }
        prevSuccessAllocateRef.current = isSuccessAllocate
    }, [isSuccessAllocate])

    // Handle successful standalone rewards split
    useEffect(() => {
        if (isSuccessSplitStandalone && !prevSuccessSplitStandaloneRef.current) {
            setSplitCoverageAgentId("")
            setSplitRewardsPercent(100)
        }
        prevSuccessSplitStandaloneRef.current = isSuccessSplitStandalone
    }, [isSuccessSplitStandalone])

    // Handle transaction receipt errors
    useEffect(() => {
        if (isErrorRegister && errorRegister && hashRegister && hasShownErrorRegister.current !== hashRegister) {
            hasShownErrorRegister.current = hashRegister
            const decodedError = decodeContractError(errorRegister)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorRegister, errorRegister, hashRegister])

    useEffect(() => {
        if (isErrorUpdate && errorUpdate && hashUpdate && hasShownErrorUpdate.current !== hashUpdate) {
            hasShownErrorUpdate.current = hashUpdate
            const decodedError = decodeContractError(errorUpdate)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorUpdate, errorUpdate, hashUpdate])

    useEffect(() => {
        if (
            isErrorRegisterAgent &&
            errorRegisterAgent &&
            hashRegisterAgent &&
            hasShownErrorRegisterAgent.current !== hashRegisterAgent
        ) {
            hasShownErrorRegisterAgent.current = hashRegisterAgent
            const decodedError = decodeContractError(errorRegisterAgent)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorRegisterAgent, errorRegisterAgent, hashRegisterAgent])

    useEffect(() => {
        if (isErrorAllocate && errorAllocate && hashAllocate && hasShownErrorAllocate.current !== hashAllocate) {
            hasShownErrorAllocate.current = hashAllocate
            const decodedError = decodeContractError(errorAllocate)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorAllocate, errorAllocate, hashAllocate])

    useEffect(() => {
        if (
            isErrorSplitStandalone &&
            errorSplitStandalone &&
            hashSplitStandalone &&
            hasShownErrorSplitStandalone.current !== hashSplitStandalone
        ) {
            hasShownErrorSplitStandalone.current = hashSplitStandalone
            const decodedError = decodeContractError(errorSplitStandalone)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorSplitStandalone, errorSplitStandalone, hashSplitStandalone])

    // Handler functions
    const handleRegisterAsOperator = () => {
        if (!eigenAddresses?.delegationManager) {
            toast.error("EigenLayer addresses not loaded")
            return
        }

        if (!metadataURI) {
            toast.error("Metadata URI is required")
            return
        }

        const approver = delegationApprover && isAddress(delegationApprover) 
            ? delegationApprover 
            : "0x0000000000000000000000000000000000000000"

        const optOutBlocks = Number(stakerOptOutWindowBlocks) || 0

        writeRegisterOperator(
            {
                address: eigenAddresses.delegationManager,
                abi: iDelegationManagerAbi,
                functionName: "registerAsOperator",
                args: [approver as Address, optOutBlocks, metadataURI],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, { duration: 8000 })
                },
            }
        )
    }

    const handleUpdateMetadata = () => {
        if (!eigenAddresses?.delegationManager || !connectedAddress) {
            toast.error("Not connected or addresses not loaded")
            return
        }

        if (!newMetadataURI) {
            toast.error("New metadata URI is required")
            return
        }

        writeUpdateMetadata(
            {
                address: eigenAddresses.delegationManager,
                abi: iDelegationManagerAbi,
                functionName: "updateOperatorMetadataURI",
                args: [connectedAddress, newMetadataURI],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, { duration: 8000 })
                },
            }
        )
    }

    const handleRegisterToCoverageAgent = () => {
        if (!eigenAddresses?.allocationManager || !connectedAddress) {
            toast.error("Not connected or addresses not loaded")
            return
        }

        if (!selectedCoverageAgent || !isAddress(selectedCoverageAgent)) {
            toast.error("Please select a valid coverage agent")
            return
        }

        if (registerOperatorSetId === undefined) {
            toast.error("Loading operator set ID...")
            return
        }

        writeRegisterCoverageAgent(
            {
                address: eigenAddresses.allocationManager,
                abi: iAllocationManagerAbi,
                functionName: "registerForOperatorSets",
                args: [
                    connectedAddress,
                    {
                        avs: serviceManagerAddress,
                        operatorSetIds: [registerOperatorSetId as number],
                        data: "0x",
                    },
                ],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, { duration: 8000 })
                },
            }
        )
    }

    const handleSetRewardsSplitStandalone = () => {
        if (!eigenAddresses?.rewardsCoordinator || !connectedAddress) {
            toast.error("Not connected or addresses not loaded")
            return
        }

        if (!splitCoverageAgent || !isAddress(splitCoverageAgent)) {
            toast.error("Please select a valid coverage agent")
            return
        }

        const split = Math.round(splitRewardsPercent * 100) // basis points (10000 = 100%)
        if (split < 0 || split > 10000) {
            toast.error("Rewards split must be between 0% and 100%")
            return
        }

        if (splitOperatorSetId === undefined) {
            toast.error("Loading operator set ID...")
            return
        }

        writeSetRewardsSplitStandalone(
            {
                address: eigenAddresses.rewardsCoordinator,
                abi: iRewardsCoordinatorAbi,
                functionName: "setOperatorSetSplit",
                args: [
                    connectedAddress,
                    {
                        avs: serviceManagerAddress,
                        id: splitOperatorSetId as number,
                    },
                    split,
                ],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Rewards split updated: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, { duration: 8000 })
                },
            }
        )
    }

    const addAllocateStrategy = () => {
        setAllocateStrategies([...allocateStrategies, { address: "", magnitude: 0 }])
    }

    const removeAllocateStrategy = (index: number) => {
        if (allocateStrategies.length > 1) {
            setAllocateStrategies(allocateStrategies.filter((_, i) => i !== index))
        }
    }

    const updateAllocateStrategyAddress = (index: number, value: string) => {
        const next = [...allocateStrategies]
        next[index].address = value
        setAllocateStrategies(next)
    }

    const updateAllocateStrategyMagnitude = (index: number, value: number) => {
        const next = [...allocateStrategies]
        next[index].magnitude = value
        setAllocateStrategies(next)
    }

    const handleAllocate = () => {
        if (!eigenAddresses?.allocationManager || !connectedAddress) {
            toast.error("Not connected or addresses not loaded")
            return
        }

        if (!allocateCoverageAgent || !isAddress(allocateCoverageAgent)) {
            toast.error("Please select a valid coverage agent")
            return
        }

        const validStrategies = allocateStrategies.filter(
            (s) => s.address && isAddress(s.address) && s.magnitude >= 0
        )
        if (validStrategies.length === 0) {
            toast.error("Please add at least one strategy with an address and allocation %")
            return
        }

        if (allocateOperatorSetId === undefined) {
            toast.error("Loading operator set ID...")
            return
        }

        const maxMagnitudes = maxAllocationMagnitudes as bigint[] | undefined
        if (!maxMagnitudes || maxMagnitudes.length !== validStrategies.length) {
            toast.error("Loading max allocations for strategies...")
            return
        }

        const magnitudes = validStrategies.map(
            (s, i) => (maxMagnitudes[i] * BigInt(s.magnitude)) / 100n
        )
        const hasZeroMax = magnitudes.some((_, i) => maxMagnitudes[i] === 0n)
        if (hasZeroMax) {
            toast.error("No allocatable stake for one or more selected strategies")
            return
        }

        writeAllocate(
            {
                address: eigenAddresses.allocationManager,
                abi: iAllocationManagerAbi,
                functionName: "modifyAllocations",
                args: [
                    connectedAddress,
                    [
                        {
                            operatorSet: {
                                avs: serviceManagerAddress,
                                id: allocateOperatorSetId as number,
                            },
                            strategies: validStrategies.map((s) => s.address as Address),
                            newMagnitudes: magnitudes,
                        },
                    ],
                ],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, { duration: 8000 })
                },
            }
        )
    }

    if (!connectedAddress) {
        return (
            <Card>
                <CardHeader>
                    <CardTitle>Operator Management</CardTitle>
                    <CardDescription>
                        Connect your wallet to manage operator functionality
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <p className="text-sm text-muted-foreground">
                        Please connect your wallet to use operator management features.
                    </p>
                </CardContent>
            </Card>
        )
    }

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center gap-2">
                    <User className="size-5" />
                    <CardTitle>Operator Management</CardTitle>
                </div>
                <CardDescription>
                    Manage EigenLayer operator registration and allocation directly from your wallet
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
                {/* Operator Status */}
                <div className="rounded-lg border bg-muted/30 p-4">
                    <div className="flex items-center justify-between">
                        <div>
                            <p className="text-sm font-medium">Operator Status</p>
                            <p className="text-xs text-muted-foreground mt-1">
                                Connected Wallet: <CopyableAddress address={connectedAddress} />
                            </p>
                        </div>
                        <Badge variant={isOperator ? "default" : "secondary"}>
                            {isOperator ? "Registered Operator" : "Not Registered"}
                        </Badge>
                    </div>
                    {isOperator && currentMetadataURI && (
                        <div className="mt-3 pt-3 border-t">
                            <p className="text-xs text-muted-foreground">Current Metadata URI:</p>
                            <p className="text-xs font-mono mt-1 break-all">{currentMetadataURI}</p>
                        </div>
                    )}
                </div>

                {!isOperator ? (
                    <>
                        <Separator />
                        {/* Register as Operator */}
                        <div className="space-y-4">
                            <div>
                                <h4 className="text-sm font-medium flex items-center gap-2">
                                    <User className="size-4" />
                                    Register as Operator
                                </h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Register your wallet as an EigenLayer operator to provide coverage
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="metadataURI">Metadata URI *</Label>
                                <Input
                                    id="metadataURI"
                                    placeholder="https://... or ipfs://..."
                                    value={metadataURI}
                                    onChange={(e) => setMetadataURI(e.target.value)}
                                    disabled={isPendingRegister || isConfirmingRegister}
                                />
                                <p className="text-xs text-muted-foreground">
                                    URL to operator metadata (JSON with name, description, etc.)
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="delegationApprover">
                                    Delegation Approver (optional)
                                </Label>
                                <Input
                                    id="delegationApprover"
                                    placeholder="0x... (leave empty for no approver)"
                                    value={delegationApprover}
                                    onChange={(e) => setDelegationApprover(e.target.value)}
                                    className="font-mono"
                                    disabled={isPendingRegister || isConfirmingRegister}
                                />
                                {delegationApprover && !isAddress(delegationApprover) && (
                                    <p className="text-xs text-destructive">Invalid address</p>
                                )}
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="stakerOptOut">Staker Opt-Out Window (blocks)</Label>
                                <Input
                                    id="stakerOptOut"
                                    type="number"
                                    placeholder="0"
                                    value={stakerOptOutWindowBlocks}
                                    onChange={(e) => setStakerOptOutWindowBlocks(e.target.value)}
                                    disabled={isPendingRegister || isConfirmingRegister}
                                />
                                <p className="text-xs text-muted-foreground">
                                    Number of blocks before stakers can opt-out (0 for immediate)
                                </p>
                            </div>

                            <Button
                                onClick={handleRegisterAsOperator}
                                disabled={
                                    !metadataURI || isPendingRegister || isConfirmingRegister
                                }
                                className="w-full"
                            >
                                {isPendingRegister || isConfirmingRegister ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <User className="mr-2 size-4" />
                                )}
                                {isPendingRegister
                                    ? "Confirm in wallet..."
                                    : isConfirmingRegister
                                      ? "Registering..."
                                      : "Register as Operator"}
                            </Button>

                            {isSuccessRegister && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Successfully registered as operator!
                                </p>
                            )}
                        </div>
                    </>
                ) : (
                    <>
                        <Separator />
                        {/* Update Metadata */}
                        <div className="space-y-4">
                            <div>
                                <h4 className="text-sm font-medium flex items-center gap-2">
                                    <LinkIcon className="size-4" />
                                    Update Operator Metadata
                                </h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Update your operator metadata URI
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="newMetadataURI">New Metadata URI</Label>
                                <Input
                                    id="newMetadataURI"
                                    placeholder="https://... or ipfs://..."
                                    value={newMetadataURI}
                                    onChange={(e) => setNewMetadataURI(e.target.value)}
                                    disabled={isPendingUpdate || isConfirmingUpdate}
                                />
                            </div>

                            <Button
                                onClick={handleUpdateMetadata}
                                disabled={!newMetadataURI || isPendingUpdate || isConfirmingUpdate}
                                className="w-full"
                            >
                                {isPendingUpdate || isConfirmingUpdate ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <LinkIcon className="mr-2 size-4" />
                                )}
                                {isPendingUpdate
                                    ? "Confirm in wallet..."
                                    : isConfirmingUpdate
                                      ? "Updating..."
                                      : "Update Metadata"}
                            </Button>

                            {isSuccessUpdate && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Metadata updated successfully!
                                </p>
                            )}
                        </div>

                        <Separator />

                        {/* Register to Coverage Agent */}
                        <div className="space-y-4">
                            <div>
                                <h4 className="text-sm font-medium">Register to Coverage Agent</h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Register your operator to a coverage agent's operator set
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label>Coverage Agent</Label>
                                <CoverageAgentSelect
                                    selectedContractId={selectedCoverageAgentId}
                                    onSelectedContractIdChange={setSelectedCoverageAgentId}
                                    contracts={coverageAgents}
                                    disabled={isPendingRegisterAgent || isConfirmingRegisterAgent}
                                />
                            </div>

                            <Button
                                onClick={handleRegisterToCoverageAgent}
                                disabled={
                                    !selectedCoverageAgent ||
                                    isPendingRegisterAgent ||
                                    isConfirmingRegisterAgent
                                }
                                className="w-full"
                            >
                                {isPendingRegisterAgent || isConfirmingRegisterAgent ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <DollarSign className="mr-2 size-4" />
                                )}
                                {isPendingRegisterAgent
                                    ? "Confirm in wallet..."
                                    : isConfirmingRegisterAgent
                                      ? "Registering..."
                                      : "Register to Operator Set"}
                            </Button>

                            {isSuccessRegisterAgent && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Registered to coverage agent!
                                </p>
                            )}
                        </div>

                        <Separator />

                        {/* Allocate to Strategy */}
                        <div className="space-y-4">
                            <div>
                                <h4 className="text-sm font-medium">Allocate to Strategy</h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Allocate stake to a coverage agent and strategy (can only be done
                                    after ~17.5 days from registration)
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label>Coverage Agent</Label>
                                <CoverageAgentSelect
                                    selectedContractId={allocateCoverageAgentId}
                                    onSelectedContractIdChange={setAllocateCoverageAgentId}
                                    contracts={coverageAgents}
                                    disabled={isPendingAllocate || isConfirmingAllocate}
                                />
                            </div>

                            <div className="space-y-3">
                                <div className="flex items-center justify-between">
                                    <Label>Strategy Allocations</Label>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        onClick={addAllocateStrategy}
                                        disabled={isPendingAllocate || isConfirmingAllocate}
                                    >
                                        <Plus className="mr-1 size-3" />
                                        Add Strategy
                                    </Button>
                                </div>

                                <p className="text-xs text-muted-foreground">
                                    Configure which strategies to allocate to and their allocation
                                    percentages
                                </p>

                                <div className="space-y-3">
                                    {allocateStrategies.map((strategy, index) => (
                                        <div
                                            key={index}
                                            className="flex gap-2 items-start p-3 rounded-lg border bg-muted/30"
                                        >
                                            <div className="flex-1 space-y-3">
                                                <StrategySelect
                                                    value={strategy.address}
                                                    onValueChange={(value) =>
                                                        updateAllocateStrategyAddress(index, value)
                                                    }
                                                    serviceManagerAddress={serviceManagerAddress}
                                                    chainId={chainId}
                                                    placeholder="Select strategy..."
                                                    disabled={
                                                        isPendingAllocate || isConfirmingAllocate
                                                    }
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
                                                            updateAllocateStrategyMagnitude(
                                                                index,
                                                                values[0] ?? 0
                                                            )
                                                        }
                                                        min={0}
                                                        max={100}
                                                        step={1}
                                                        disabled={
                                                            isPendingAllocate || isConfirmingAllocate
                                                        }
                                                    />
                                                </div>
                                            </div>
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                size="icon"
                                                onClick={() => removeAllocateStrategy(index)}
                                                disabled={
                                                    allocateStrategies.length === 1 ||
                                                    isPendingAllocate ||
                                                    isConfirmingAllocate
                                                }
                                                className="shrink-0 text-muted-foreground hover:text-destructive"
                                            >
                                                <Trash2 className="size-4" />
                                            </Button>
                                        </div>
                                    ))}
                                </div>
                            </div>

                            <Button
                                onClick={handleAllocate}
                                disabled={
                                    !allocateCoverageAgent ||
                                    allocateStrategies.every(
                                        (s) => !s.address || !isAddress(s.address) || s.magnitude <= 0
                                    ) ||
                                    isPendingAllocate ||
                                    isConfirmingAllocate ||
                                    !maxAllocationMagnitudes ||
                                    (maxAllocationMagnitudes as bigint[]).length !==
                                        allocateStrategyAddresses.length
                                }
                                className="w-full"
                            >
                                {isPendingAllocate || isConfirmingAllocate ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <DollarSign className="mr-2 size-4" />
                                )}
                                {isPendingAllocate
                                    ? "Confirm in wallet..."
                                    : isConfirmingAllocate
                                      ? "Allocating..."
                                      : "Allocate Stake"}
                            </Button>

                            {isSuccessAllocate && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Stake allocated successfully!
                                </p>
                            )}
                        </div>

                        <Separator />

                        {/* Update Rewards Split */}
                        <div className="space-y-4">
                            <div>
                                <h4 className="text-sm font-medium flex items-center gap-2">
                                    <DollarSign className="size-4" />
                                    Update Rewards Split
                                </h4>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Update the rewards split for a coverage agent you're already
                                    registered to
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label>Coverage Agent</Label>
                                <CoverageAgentSelect
                                    selectedContractId={splitCoverageAgentId}
                                    onSelectedContractIdChange={setSplitCoverageAgentId}
                                    contracts={coverageAgents}
                                    disabled={
                                        isPendingSplitStandalone || isConfirmingSplitStandalone
                                    }
                                />
                            </div>

                            <div className="space-y-2">
                                <div className="flex items-center justify-between">
                                    <Label>Rewards Split</Label>
                                    <span className="text-sm font-medium tabular-nums">
                                        {splitRewardsPercent}%
                                    </span>
                                </div>
                                <Slider
                                    value={[splitRewardsPercent]}
                                    onValueChange={(value) =>
                                        setSplitRewardsPercent(value[0] ?? 0)
                                    }
                                    min={0}
                                    max={100}
                                    step={1}
                                    disabled={
                                        isPendingSplitStandalone ||
                                        isConfirmingSplitStandalone
                                    }
                                />
                                <p className="text-xs text-muted-foreground">
                                    Percentage of rewards to send to the coverage agent
                                </p>
                            </div>

                            <Button
                                onClick={handleSetRewardsSplitStandalone}
                                disabled={
                                    !splitCoverageAgent ||
                                    isPendingSplitStandalone ||
                                    isConfirmingSplitStandalone
                                }
                                className="w-full"
                            >
                                {isPendingSplitStandalone || isConfirmingSplitStandalone ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <DollarSign className="mr-2 size-4" />
                                )}
                                {isPendingSplitStandalone
                                    ? "Confirm in wallet..."
                                    : isConfirmingSplitStandalone
                                      ? "Updating..."
                                      : "Update Rewards Split"}
                            </Button>

                            {isSuccessSplitStandalone && (
                                <p className="flex items-center gap-2 text-sm text-green-600">
                                    <CheckCircle2 className="size-4" />
                                    Rewards split updated successfully!
                                </p>
                            )}
                        </div>

                        {/* Show registered sets */}
                        {registeredSets && (registeredSets as Array<{ avs: Address; id: number }>).length > 0 && (
                            <>
                                <Separator />
                                <div className="space-y-2">
                                    <h4 className="text-sm font-medium">Registered Operator Sets</h4>
                                    <div className="space-y-2">
                                        {(registeredSets as Array<{ avs: Address; id: number }>).map(
                                            (set, index: number) => (
                                                <div
                                                    key={index}
                                                    className="rounded-lg border bg-muted/30 p-3 text-xs"
                                                >
                                                    <div className="flex items-center justify-between">
                                                        <span className="text-muted-foreground">
                                                            Operator Set ID:
                                                        </span>
                                                        <span className="font-mono">{set.id}</span>
                                                    </div>
                                                    <div className="flex items-center justify-between mt-1">
                                                        <span className="text-muted-foreground">
                                                            AVS:
                                                        </span>
                                                        <CopyableAddress address={set.avs} />
                                                    </div>
                                                </div>
                                            )
                                        )}
                                    </div>
                                </div>
                            </>
                        )}
                    </>
                )}
            </CardContent>
        </Card>
    )
}
