import { useState, useEffect, useRef, useMemo } from "react"
import { type Address, isAddress, BaseError } from "viem"
import {
    useReadContract,
    useWriteContract,
    useWaitForTransactionReceipt,
    useAccount,
    useConfig,
} from "wagmi"
import { readContract } from "wagmi/actions"
import {
    Loader2,
    CheckCircle2,
    User,
    DollarSign,
    Link as LinkIcon,
    Plus,
    Trash2,
    ExternalLink,
} from "lucide-react"
import { Link } from "react-router-dom"
import { toast } from "sonner"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog"
import { useContracts } from "@/hooks/use-contracts"
import { generateContractName } from "@/lib/utils"
import { getSupportedChainsInfo } from "@/lib/wagmi"
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
    const config = useConfig()
    const { coverageAgents, serviceManagers } = useChainFilteredContracts(chainId as number)
    const { addContract, contracts } = useContracts()

    // Add AVS dialog state (quick-add AVS from registered operator set)
    const [addAvsDialogOpen, setAddAvsDialogOpen] = useState(false)
    const [addAvsPayload, setAddAvsPayload] = useState<{
        address: Address
        chainId: number
    } | null>(null)
    const [addAvsName, setAddAvsName] = useState("")

    // State for register as operator
    const [metadataURI, setMetadataURI] = useState("")
    const [delegationApprover, setDelegationApprover] = useState<string>("")
    const [stakerOptOutWindowBlocks, setStakerOptOutWindowBlocks] = useState("0")

    // State for update metadata
    const [newMetadataURI, setNewMetadataURI] = useState("")

    // Single coverage agent selection used for register, allocate, and rewards split
    const [coverageAgentId, setCoverageAgentId] = useState<string>("")

    // State for allocate (strategies list)
    const [allocateStrategies, setAllocateStrategies] = useState<
        Array<{ address: string; magnitude: number }>
    >([{ address: "", magnitude: 0 }])

    const [splitRewardsPercent, setSplitRewardsPercent] = useState(0)

    // Selected coverage agent address (used across register, allocate, rewards split)
    const selectedCoverageAgent = coverageAgents.find((c) => c.id === coverageAgentId)?.address

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

    // Get operator set ID for the selected coverage agent (used for register, allocate, rewards split)
    const { data: operatorSetId } = useReadContract({
        address: serviceManagerAddress,
        abi: iEigenServiceManagerAbi,
        functionName: "getOperatorSetId",
        args:
            selectedCoverageAgent && isAddress(selectedCoverageAgent)
                ? [selectedCoverageAgent as Address]
                : undefined,
        chainId,
        query: {
            enabled: !!chainId && !!selectedCoverageAgent && isAddress(selectedCoverageAgent),
        },
    })

    // Whether the operator is already registered to the selected coverage agent's operator set
    const isRegisteredToSelectedAgent = useMemo(() => {
        if (!registeredSets || operatorSetId === undefined || !serviceManagerAddress) return false
        const sets = registeredSets as Array<{ avs: Address; id: number }>
        return sets.some(
            (set) =>
                set.avs?.toLowerCase() === serviceManagerAddress?.toLowerCase() &&
                Number(set.id) === Number(operatorSetId)
        )
    }, [registeredSets, operatorSetId, serviceManagerAddress])

    // Coverage agent has no operator set on this provider (operatorSetId === 0) → must register from coverage agent page
    const agentNotRegisteredToProvider =
        !!coverageAgentId && operatorSetId !== undefined && Number(operatorSetId) === 0

    // Get current rewards split from chain for the selected coverage agent
    const operatorSetForSplit =
        operatorSetId !== undefined && connectedAddress && serviceManagerAddress
            ? { avs: serviceManagerAddress, id: Number(operatorSetId) }
            : undefined
    const splitReadArgs =
        connectedAddress && operatorSetForSplit
            ? ([connectedAddress, operatorSetForSplit] as const)
            : undefined
    const { data: currentRewardsSplitBps } = useReadContract({
        address: eigenAddresses?.rewardsCoordinator,
        abi: iRewardsCoordinatorAbi,
        functionName: "getOperatorSetSplit",
        args: splitReadArgs,
        chainId,
        query: {
            enabled:
                !!eigenAddresses?.rewardsCoordinator &&
                !!chainId &&
                !!splitReadArgs &&
                !!connectedAddress,
        },
    })

    // Sync slider to current on-chain rewards split when coverage agent selection changes (only when operator is registered to agent)
    useEffect(() => {
        if (!coverageAgentId) return
        if (!isRegisteredToSelectedAgent) {
            setSplitRewardsPercent(0)
            return
        }
        if (currentRewardsSplitBps !== undefined) {
            const percent = Math.round(Number(currentRewardsSplitBps) / 100)
            setSplitRewardsPercent(percent)
        }
    }, [coverageAgentId, currentRewardsSplitBps, isRegisteredToSelectedAgent])

    // Load this operator's allocated strategies for the selected coverage agent's operator set
    const { data: allocatedStrategiesForSet } = useReadContract({
        address: eigenAddresses?.allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getAllocatedStrategies",
        args:
            operatorSetForSplit && connectedAddress
                ? [connectedAddress, operatorSetForSplit]
                : undefined,
        chainId,
        query: {
            enabled:
                !!eigenAddresses?.allocationManager &&
                !!chainId &&
                !!operatorSetForSplit &&
                !!connectedAddress,
        },
    })

    // Pre-fill strategy allocations form when coverage agent is selected and we have on-chain allocations
    useEffect(() => {
        if (
            !chainId ||
            !connectedAddress ||
            !operatorSetForSplit ||
            !eigenAddresses?.allocationManager ||
            allocatedStrategiesForSet === undefined
        ) {
            return
        }
        const strategies = allocatedStrategiesForSet as Address[]
        if (strategies.length === 0) {
            setAllocateStrategies([{ address: "", magnitude: 0 }])
            return
        }
        let cancelled = false
        const run = async () => {
            try {
                const [allocations, maxMagnitudes] = await Promise.all([
                    Promise.all(
                        strategies.map((addr) =>
                            readContract(config, {
                                address: eigenAddresses!.allocationManager!,
                                abi: iAllocationManagerAbi,
                                functionName: "getAllocation",
                                args: [connectedAddress, operatorSetForSplit!, addr],
                                chainId,
                            })
                        )
                    ),
                    readContract(config, {
                        address: eigenAddresses!.allocationManager!,
                        abi: iAllocationManagerAbi,
                        functionName: "getMaxMagnitudes",
                        args: [connectedAddress, strategies],
                        chainId,
                    }),
                ])
                if (cancelled) return
                const maxArr = maxMagnitudes as bigint[]
                const next = strategies.map((addr, i) => {
                    const current = allocations[i]?.currentMagnitude ?? 0n
                    const max = maxArr?.[i] ?? 1n
                    const pct =
                        max === 0n ? 0 : Math.min(100, Math.round(Number((current * 100n) / max)))
                    return { address: addr, magnitude: pct }
                })
                setAllocateStrategies(next)
            } catch {
                if (!cancelled)
                    setAllocateStrategies(
                        strategies.map((addr) => ({ address: addr, magnitude: 0 }))
                    )
            }
        }
        run()
        return () => {
            cancelled = true
        }
        // Refill only when selection or allocated data changes; omit operatorSetForSplit/eigenAddresses to avoid object-ref churn
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        chainId,
        connectedAddress,
        coverageAgentId,
        operatorSetId,
        eigenAddresses?.allocationManager,
        allocatedStrategiesForSet,
        config,
    ])

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
        }
        prevSuccessRegisterAgentRef.current = isSuccessRegisterAgent
    }, [isSuccessRegisterAgent, refetchRegisteredSets])

    // Handle successful allocation (reset strategy list only; keep coverage agent selected)
    useEffect(() => {
        if (isSuccessAllocate && !prevSuccessAllocateRef.current) {
            setAllocateStrategies([{ address: "", magnitude: 0 }])
        }
        prevSuccessAllocateRef.current = isSuccessAllocate
    }, [isSuccessAllocate])

    // Handle successful standalone rewards split (slider syncs from chain via other effect)
    useEffect(() => {
        if (isSuccessSplitStandalone && !prevSuccessSplitStandaloneRef.current) {
            // No state to clear; selection and slider stay in sync with chain
        }
        prevSuccessSplitStandaloneRef.current = isSuccessSplitStandalone
    }, [isSuccessSplitStandalone])

    // Handle transaction receipt errors
    useEffect(() => {
        if (
            isErrorRegister &&
            errorRegister &&
            hashRegister &&
            hasShownErrorRegister.current !== hashRegister
        ) {
            hasShownErrorRegister.current = hashRegister
            const decodedError = decodeContractError(errorRegister)
            toast.error(`Transaction failed: ${decodedError}`, { duration: 10000 })
        }
    }, [isErrorRegister, errorRegister, hashRegister])

    useEffect(() => {
        if (
            isErrorUpdate &&
            errorUpdate &&
            hashUpdate &&
            hasShownErrorUpdate.current !== hashUpdate
        ) {
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
        if (
            isErrorAllocate &&
            errorAllocate &&
            hashAllocate &&
            hasShownErrorAllocate.current !== hashAllocate
        ) {
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

        const approver =
            delegationApprover && isAddress(delegationApprover)
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

        if (operatorSetId === undefined) {
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
                        operatorSetIds: [operatorSetId as number],
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

        if (!selectedCoverageAgent || !isAddress(selectedCoverageAgent)) {
            toast.error("Please select a valid coverage agent")
            return
        }

        const split = Math.round(splitRewardsPercent * 100) // basis points (10000 = 100%)
        if (split < 0 || split > 10000) {
            toast.error("Rewards split must be between 0% and 100%")
            return
        }

        if (operatorSetId === undefined) {
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
                        id: operatorSetId as number,
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

        if (!selectedCoverageAgent || !isAddress(selectedCoverageAgent)) {
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

        if (operatorSetId === undefined) {
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
                                id: operatorSetId as number,
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
        <>
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-2">
                        <User className="size-5" />
                        <CardTitle>Operator Management</CardTitle>
                    </div>
                    <CardDescription>
                        Manage EigenLayer operator registration and allocation directly from your
                        wallet
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
                                <p className="text-xs text-muted-foreground">
                                    Current Metadata URI:
                                </p>
                                <p className="text-xs font-mono mt-1 break-all">
                                    {currentMetadataURI}
                                </p>
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
                                        Register your wallet as an EigenLayer operator to provide
                                        coverage
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
                                    <Label htmlFor="stakerOptOut">
                                        Staker Opt-Out Window (blocks)
                                    </Label>
                                    <Input
                                        id="stakerOptOut"
                                        type="number"
                                        placeholder="0"
                                        value={stakerOptOutWindowBlocks}
                                        onChange={(e) =>
                                            setStakerOptOutWindowBlocks(e.target.value)
                                        }
                                        disabled={isPendingRegister || isConfirmingRegister}
                                    />
                                    <p className="text-xs text-muted-foreground">
                                        Number of blocks before stakers can opt-out (0 for
                                        immediate)
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
                                    disabled={
                                        !newMetadataURI || isPendingUpdate || isConfirmingUpdate
                                    }
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

                            <div className="space-y-4 border p-4 bg-muted/30">
                                {/* Coverage Agent selection - used for register, allocate, and rewards split */}
                                <div className="space-y-2">
                                    <h3>Coverage Agent Setup</h3>
                                    <CoverageAgentSelect
                                        selectedContractId={coverageAgentId}
                                        onSelectedContractIdChange={setCoverageAgentId}
                                        contracts={coverageAgents}
                                        disabled={
                                            isPendingRegisterAgent ||
                                            isConfirmingRegisterAgent ||
                                            isPendingAllocate ||
                                            isConfirmingAllocate ||
                                            isPendingSplitStandalone ||
                                            isConfirmingSplitStandalone
                                        }
                                    />
                                    <p className="text-xs text-muted-foreground">
                                        Select once to use for Register, Allocate to Strategies, and
                                        Update Rewards Split below
                                    </p>
                                    {agentNotRegisteredToProvider && (
                                        <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 space-y-2 text-xs">
                                            <p className="text-muted-foreground">
                                                This coverage agent is not registered with this
                                                coverage provider. Register it from the coverage
                                                agent page.
                                            </p>
                                            <Link
                                                to={`/interact/${coverageAgentId}`}
                                                className="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium bg-primary text-primary-foreground hover:opacity-90"
                                            >
                                                <ExternalLink className="size-3.5" />
                                                Go to Coverage Agent
                                            </Link>
                                        </div>
                                    )}
                                    {operatorSetId !== undefined &&
                                        Number(operatorSetId) !== 0 &&
                                        coverageAgentId && (
                                            <div className="rounded-lg border bg-muted/30 px-3 py-2 text-xs">
                                                <span className="text-muted-foreground">
                                                    Operator set for this coverage agent:{" "}
                                                </span>
                                                <span className="font-mono font-medium">
                                                    #{Number(operatorSetId)}
                                                </span>
                                            </div>
                                        )}
                                </div>

                                {/* Register to Coverage Agent */}
                                <div className="space-y-4">
                                    <div>
                                        <h4 className="text-sm font-medium">
                                            Register to Coverage Agent
                                        </h4>
                                        <p className="text-xs text-muted-foreground mt-1">
                                            Register your operator to a coverage agent's operator
                                            set
                                        </p>
                                    </div>

                                    <Button
                                        onClick={handleRegisterToCoverageAgent}
                                        disabled={
                                            !coverageAgentId ||
                                            !selectedCoverageAgent ||
                                            agentNotRegisteredToProvider ||
                                            isRegisteredToSelectedAgent ||
                                            isPendingRegisterAgent ||
                                            isConfirmingRegisterAgent
                                        }
                                        className="w-full"
                                    >
                                        {isPendingRegisterAgent || isConfirmingRegisterAgent ? (
                                            <Loader2 className="mr-2 size-4 animate-spin" />
                                        ) : isRegisteredToSelectedAgent ? (
                                            <CheckCircle2 className="mr-2 size-4" />
                                        ) : (
                                            <DollarSign className="mr-2 size-4" />
                                        )}
                                        {isPendingRegisterAgent
                                            ? "Confirm in wallet..."
                                            : isConfirmingRegisterAgent
                                              ? "Registering..."
                                              : isRegisteredToSelectedAgent
                                                ? "Already Registered"
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
                                    <div className="space-y-3">
                                        <div className="flex items-center justify-between">
                                            <Label>Strategy Allocations</Label>
                                            <Button
                                                type="button"
                                                variant="outline"
                                                size="sm"
                                                onClick={addAllocateStrategy}
                                                disabled={
                                                    agentNotRegisteredToProvider ||
                                                    isPendingAllocate ||
                                                    isConfirmingAllocate
                                                }
                                            >
                                                <Plus className="mr-1 size-3" />
                                                Add Strategy
                                            </Button>
                                        </div>

                                        <p className="text-xs text-muted-foreground">
                                            Configure which strategies to allocate to and their
                                            allocation percentages. Current allocations are
                                            pre-filled when you select a coverage agent.
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
                                                                updateAllocateStrategyAddress(
                                                                    index,
                                                                    value
                                                                )
                                                            }
                                                            serviceManagerAddress={
                                                                serviceManagerAddress
                                                            }
                                                            chainId={chainId}
                                                            placeholder="Select strategy..."
                                                            disabled={
                                                                agentNotRegisteredToProvider ||
                                                                isPendingAllocate ||
                                                                isConfirmingAllocate
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
                                                                    agentNotRegisteredToProvider ||
                                                                    isPendingAllocate ||
                                                                    isConfirmingAllocate
                                                                }
                                                            />
                                                        </div>
                                                    </div>
                                                    <Button
                                                        type="button"
                                                        variant="ghost"
                                                        size="icon"
                                                        onClick={() =>
                                                            removeAllocateStrategy(index)
                                                        }
                                                        disabled={
                                                            allocateStrategies.length === 1 ||
                                                            agentNotRegisteredToProvider ||
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
                                            agentNotRegisteredToProvider ||
                                            !selectedCoverageAgent ||
                                            allocateStrategies.every(
                                                (s) =>
                                                    !s.address ||
                                                    !isAddress(s.address) ||
                                                    s.magnitude <= 0
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
                                            Update the rewards split for the selected coverage agent
                                        </p>
                                    </div>

                                    <div className="space-y-2">
                                        <div className="flex items-center justify-between">
                                            <Label>Rewards Split</Label>
                                            <span className="text-sm font-medium tabular-nums">
                                                {!isRegisteredToSelectedAgent
                                                    ? 0
                                                    : splitRewardsPercent}
                                                %
                                            </span>
                                        </div>
                                        <Slider
                                            value={[
                                                !isRegisteredToSelectedAgent
                                                    ? 0
                                                    : splitRewardsPercent,
                                            ]}
                                            onValueChange={(value) =>
                                                setSplitRewardsPercent(value[0] ?? 0)
                                            }
                                            min={0}
                                            max={100}
                                            step={1}
                                            disabled={
                                                agentNotRegisteredToProvider ||
                                                !isRegisteredToSelectedAgent ||
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
                                            agentNotRegisteredToProvider ||
                                            !selectedCoverageAgent ||
                                            !isRegisteredToSelectedAgent ||
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
                            </div>

                            {/* Show registered sets */}
                            {registeredSets &&
                                (registeredSets as Array<{ avs: Address; id: number }>).length >
                                    0 && (
                                    <>
                                        <Separator />
                                        <div className="space-y-2">
                                            <h4 className="text-sm font-medium">
                                                Registered Operator Sets
                                            </h4>
                                            <div className="space-y-2">
                                                {(
                                                    registeredSets as Array<{
                                                        avs: Address
                                                        id: number
                                                    }>
                                                ).map((set, index: number) => {
                                                    const isCurrentAvs =
                                                        set.avs?.toLowerCase() ===
                                                        serviceManagerAddress?.toLowerCase()
                                                    const avsInStorage = serviceManagers.find(
                                                        (c) =>
                                                            c.address?.toLowerCase() ===
                                                            set.avs?.toLowerCase()
                                                    )
                                                    return (
                                                        <div
                                                            key={index}
                                                            className="rounded-lg border bg-muted/30 p-3 text-xs"
                                                        >
                                                            <div className="flex items-center justify-between">
                                                                <span className="text-muted-foreground">
                                                                    Operator Set ID:
                                                                </span>
                                                                <div className="flex items-center gap-2">
                                                                    <span className="font-mono">
                                                                        {set.id}
                                                                    </span>
                                                                </div>
                                                            </div>
                                                            <div className="flex items-center justify-between mt-1 gap-2 flex-wrap">
                                                                <span className="text-muted-foreground">
                                                                    AVS:
                                                                </span>
                                                                <span className="flex items-center gap-2">
                                                                    {isCurrentAvs ? (
                                                                        <Badge
                                                                            variant="default"
                                                                            className="text-xs"
                                                                        >
                                                                            THIS AVS
                                                                        </Badge>
                                                                    ) : avsInStorage ? (
                                                                        <Link
                                                                            to={`/interact/${avsInStorage.id}`}
                                                                            className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium bg-primary text-primary-foreground hover:opacity-90"
                                                                        >
                                                                            <ExternalLink className="size-3" />
                                                                            Go to AVS
                                                                        </Link>
                                                                    ) : (
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => {
                                                                                setAddAvsPayload({
                                                                                    address:
                                                                                        set.avs,
                                                                                    chainId:
                                                                                        chainId ??
                                                                                        0,
                                                                                })
                                                                                setAddAvsName(
                                                                                    generateContractName(
                                                                                        "CoverageProvider",
                                                                                        contracts
                                                                                    )
                                                                                )
                                                                                setAddAvsDialogOpen(
                                                                                    true
                                                                                )
                                                                            }}
                                                                            className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium border border-input bg-background hover:bg-accent hover:text-accent-foreground"
                                                                        >
                                                                            <Plus className="size-3" />
                                                                            Add
                                                                        </button>
                                                                    )}
                                                                    <CopyableAddress
                                                                        address={set.avs}
                                                                    />
                                                                </span>
                                                            </div>
                                                        </div>
                                                    )
                                                })}
                                            </div>
                                        </div>
                                    </>
                                )}
                        </>
                    )}
                </CardContent>
            </Card>

            {/* Quick-add AVS dialog */}
            <Dialog
                open={addAvsDialogOpen}
                onOpenChange={(open) => {
                    setAddAvsDialogOpen(open)
                    if (!open) setAddAvsPayload(null)
                }}
            >
                <DialogContent className="sm:max-w-md">
                    <DialogHeader>
                        <DialogTitle>Add AVS to app</DialogTitle>
                        <DialogDescription>
                            Add this AVS (Coverage Provider) to your saved contracts to open it
                            quickly later.
                        </DialogDescription>
                    </DialogHeader>
                    {addAvsPayload && (
                        <div className="space-y-4 py-2">
                            <div className="space-y-2">
                                <Label htmlFor="add-avs-name">Name</Label>
                                <Input
                                    id="add-avs-name"
                                    value={addAvsName}
                                    onChange={(e) => setAddAvsName(e.target.value)}
                                    placeholder="e.g. CoverageProvider-dune"
                                />
                            </div>
                            <div className="space-y-2">
                                <Label>Address</Label>
                                <div className="rounded-md border bg-muted/30 px-3 py-2 font-mono text-xs">
                                    <CopyableAddress address={addAvsPayload.address} />
                                </div>
                            </div>
                            <div className="space-y-2">
                                <Label>Chain</Label>
                                <p className="text-sm text-muted-foreground">
                                    {getSupportedChainsInfo().find(
                                        (c) => c.id === addAvsPayload.chainId
                                    )?.name ?? `Chain ${addAvsPayload.chainId}`}
                                </p>
                            </div>
                        </div>
                    )}
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => {
                                setAddAvsDialogOpen(false)
                                setAddAvsPayload(null)
                            }}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => {
                                if (!addAvsPayload || !addAvsName.trim()) return
                                const exists = contracts.some(
                                    (c) =>
                                        c.address.toLowerCase() ===
                                            addAvsPayload.address.toLowerCase() &&
                                        c.chainId === addAvsPayload.chainId
                                )
                                if (exists) {
                                    toast.error("This AVS is already in your contracts")
                                    return
                                }
                                const nameExists = contracts.some(
                                    (c) => c.name.toLowerCase() === addAvsName.trim().toLowerCase()
                                )
                                if (nameExists) {
                                    toast.error("A contract with this name already exists")
                                    return
                                }
                                addContract({
                                    name: addAvsName.trim(),
                                    address: addAvsPayload.address,
                                    type: "CoverageProvider",
                                    chainId: addAvsPayload.chainId,
                                })
                                toast.success("AVS added. You can open it from your contracts.")
                                setAddAvsDialogOpen(false)
                                setAddAvsPayload(null)
                            }}
                            disabled={!addAvsPayload || !addAvsName.trim()}
                        >
                            Add AVS
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    )
}
