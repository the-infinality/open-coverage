import { useMemo, useState, useEffect, useRef, useCallback } from "react"
import { type Address, formatUnits, decodeEventLog } from "viem"
import {
    RefreshCw,
    Loader2,
    Plus,
    CheckCircle2,
    Layers,
    Zap,
    Trash2,
    AlertTriangle,
} from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useConfig } from "wagmi"
import { readContract } from "wagmi/actions"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iCoverageAgentAbi, iCoverageProviderAbi } from "@/generated/abis"
import { ierc20Abi } from "@/generated/eigen-abis"
import { ContractCard } from "@/components/ContractCard"
import { CoverageProviderSelect } from "@/components/ContractSelects"
import {
    useAvailableCoverageProviders,
    getSelectedProvider,
} from "@/hooks/use-chain-filtered-contracts"
import { useContracts } from "@/hooks/use-contracts"
import { supportedChains } from "@/lib/wagmi"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { Checkbox } from "@/components/ui/checkbox"
import { CopyableAddress } from "@/components/ui/copyable-address"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog"

type SupportedChainId = (typeof supportedChains)[number]["id"]

// ABI for ExampleCoverageAgent-specific functions (not part of ICoverageAgent interface)
const exampleCoverageAgentAbi = [
    {
        type: "function",
        inputs: [
            {
                name: "requests",
                internalType: "struct ClaimCoverageRequest[]",
                type: "tuple[]",
                components: [
                    { name: "coverageProvider", internalType: "address", type: "address" },
                    { name: "positionId", internalType: "uint256", type: "uint256" },
                    { name: "amount", internalType: "uint256", type: "uint256" },
                    { name: "reward", internalType: "uint256", type: "uint256" },
                    { name: "duration", internalType: "uint256", type: "uint256" },
                ],
            },
        ],
        name: "purchaseCoverage",
        outputs: [{ name: "coverageId", internalType: "uint256", type: "uint256" }],
        stateMutability: "nonpayable",
    },
    {
        type: "function",
        inputs: [
            {
                name: "requests",
                internalType: "struct ClaimCoverageRequest[]",
                type: "tuple[]",
                components: [
                    { name: "coverageProvider", internalType: "address", type: "address" },
                    { name: "positionId", internalType: "uint256", type: "uint256" },
                    { name: "amount", internalType: "uint256", type: "uint256" },
                    { name: "reward", internalType: "uint256", type: "uint256" },
                    { name: "duration", internalType: "uint256", type: "uint256" },
                ],
            },
        ],
        name: "reserveCoverage",
        outputs: [{ name: "coverageId", internalType: "uint256", type: "uint256" }],
        stateMutability: "nonpayable",
    },
] as const

interface CoverageAgentInfoProps {
    contract: CoverageContract
}

// Claim status enum matching the contract
const CLAIM_STATUS_LABELS: Record<
    number,
    { label: string; variant: "default" | "secondary" | "destructive" | "outline" }
> = {
    0: { label: "Issued", variant: "default" },
    1: { label: "Liquidated", variant: "destructive" },
    2: { label: "Completed", variant: "secondary" },
    3: { label: "Pending Slash", variant: "outline" },
    4: { label: "Slashed", variant: "destructive" },
    5: { label: "Reserved", variant: "outline" },
}

interface CoverageClaimData {
    positionId: bigint
    amount: bigint
    duration: bigint
    createdAt: bigint
    status: number
    reward: bigint
}

interface LoadedClaimData {
    claimId: number
    providerAddress: Address
    claim: CoverageClaimData
    backing: bigint
    totalSlashAmount: bigint
}

/**
 * Claim Item component for displaying individual claims
 */
function ClaimItem({
    claimData,
    isSelected,
    onSelect,
    onRemove,
    tokenDecimals,
    tokenSymbol,
}: {
    claimData: LoadedClaimData
    isSelected: boolean
    onSelect: (selected: boolean) => void
    onRemove: () => void
    tokenDecimals: number
    tokenSymbol: string
}) {
    const { claim, claimId, providerAddress, backing, totalSlashAmount } = claimData
    const statusInfo = CLAIM_STATUS_LABELS[claim.status] || {
        label: "Unknown",
        variant: "outline" as const,
    }
    const isExpired =
        BigInt(claim.createdAt) + BigInt(claim.duration) < BigInt(Math.floor(Date.now() / 1000))
    const expiryDate = new Date(Number(claim.createdAt + claim.duration) * 1000)
    const createdDate = new Date(Number(claim.createdAt) * 1000)
    const canSlash = claim.status === 0 // Only issued claims can be slashed

    return (
        <div className="rounded-lg border p-4 space-y-3">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                    {canSlash && (
                        <Checkbox
                            checked={isSelected}
                            onChange={(e) => onSelect(e.target.checked)}
                            id={`claim-${claimId}`}
                        />
                    )}
                    <div className="flex items-center gap-2">
                        <Badge variant="outline">Claim #{claimId}</Badge>
                        <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>
                        {isExpired && <Badge variant="destructive">Expired</Badge>}
                    </div>
                </div>
                <Button variant="ghost" size="sm" onClick={onRemove} title="Remove from list">
                    <Trash2 className="size-4" />
                </Button>
            </div>

            <div className="grid gap-2 text-sm">
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Provider</span>
                    <CopyableAddress address={providerAddress} />
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Position ID</span>
                    <span className="font-mono">{claim.positionId.toString()}</span>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Amount</span>
                    <span className="font-mono">
                        {formatUnits(claim.amount, tokenDecimals)} {tokenSymbol}
                    </span>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Reward</span>
                    <span className="font-mono">
                        {formatUnits(claim.reward, tokenDecimals)} {tokenSymbol}
                    </span>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Duration</span>
                    <span className="font-mono">
                        {Math.round(Number(claim.duration) / 86400)} days
                    </span>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Created</span>
                    <span className="font-mono text-xs">{createdDate.toLocaleString()}</span>
                </div>
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Expires</span>
                    <span className="font-mono text-xs">{expiryDate.toLocaleString()}</span>
                </div>
                <Separator />
                <div className="flex items-center justify-between">
                    <span className="text-muted-foreground">Backing</span>
                    <span
                        className={`font-mono ${backing < 0n ? "text-destructive" : "text-green-600"}`}
                    >
                        {formatUnits(backing, tokenDecimals)} {tokenSymbol}
                    </span>
                </div>
                {totalSlashAmount > 0n && (
                    <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Total Slashed</span>
                        <span className="font-mono text-destructive">
                            {formatUnits(totalSlashAmount, tokenDecimals)} {tokenSymbol}
                        </span>
                    </div>
                )}
            </div>
        </div>
    )
}

/**
 * Slash Claims Dialog
 */
function SlashClaimsDialog({
    open,
    onOpenChange,
    selectedClaims,
    providerAddress,
    chainId,
    tokenDecimals,
    tokenSymbol,
    onSuccess,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    selectedClaims: LoadedClaimData[]
    providerAddress: Address
    chainId: SupportedChainId | undefined
    tokenDecimals: number
    tokenSymbol: string
    onSuccess: () => void
}) {
    const [slashAmounts, setSlashAmounts] = useState<Record<number, string>>({})
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    const prevSuccessRef = useRef(false)

    // Initialize slash amounts when claims change
    useEffect(() => {
        const initialAmounts: Record<number, string> = {}
        selectedClaims.forEach((c) => {
            initialAmounts[c.claimId] = formatUnits(c.claim.amount, tokenDecimals)
        })
        setSlashAmounts(initialAmounts)
    }, [selectedClaims, tokenDecimals])

    // Handle success
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            toast.success("Claims slashed successfully!")
            onSuccess()
            onOpenChange(false)
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, onSuccess, onOpenChange])

    const handleSlash = () => {
        const claimIds: bigint[] = []
        const amounts: bigint[] = []

        for (const claim of selectedClaims) {
            const amountStr = slashAmounts[claim.claimId]
            if (!amountStr || parseFloat(amountStr) <= 0) {
                toast.error(`Please enter a valid amount for claim #${claim.claimId}`)
                return
            }
            const amount = BigInt(Math.floor(parseFloat(amountStr) * 10 ** tokenDecimals))
            if (amount > claim.claim.amount) {
                toast.error(`Slash amount for claim #${claim.claimId} exceeds claim amount`)
                return
            }
            claimIds.push(BigInt(claim.claimId))
            amounts.push(amount)
        }

        writeContract(
            {
                address: providerAddress,
                abi: iCoverageProviderAbi,
                functionName: "slashClaims",
                args: [claimIds, amounts],
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

    const updateSlashAmount = (claimId: number, value: string) => {
        setSlashAmounts((prev) => ({ ...prev, [claimId]: value }))
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="sm:max-w-2xl">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                        <Zap className="size-5 text-destructive" />
                        Slash Claims
                    </DialogTitle>
                    <DialogDescription>
                        Configure slash amounts for each selected claim. The slash will be executed
                        on the coverage provider contract.
                    </DialogDescription>
                </DialogHeader>

                <ScrollArea className="max-h-[400px]">
                    <div className="space-y-4">
                        {selectedClaims.map((claimData) => (
                            <div
                                key={claimData.claimId}
                                className="rounded-lg border p-4 space-y-3"
                            >
                                <div className="flex items-center justify-between">
                                    <Badge variant="outline">Claim #{claimData.claimId}</Badge>
                                    <CopyableAddress address={claimData.providerAddress} />
                                </div>

                                <div className="grid gap-2 text-sm">
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Position ID</span>
                                        <span className="font-mono">
                                            {claimData.claim.positionId.toString()}
                                        </span>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Claim Amount</span>
                                        <span className="font-mono">
                                            {formatUnits(claimData.claim.amount, tokenDecimals)}{" "}
                                            {tokenSymbol}
                                        </span>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Backing</span>
                                        <span
                                            className={`font-mono ${claimData.backing < 0n ? "text-destructive" : "text-green-600"}`}
                                        >
                                            {formatUnits(claimData.backing, tokenDecimals)}{" "}
                                            {tokenSymbol}
                                        </span>
                                    </div>
                                </div>

                                <Separator />

                                <div className="space-y-2">
                                    <Label htmlFor={`slash-amount-${claimData.claimId}`}>
                                        Slash Amount ({tokenSymbol})
                                    </Label>
                                    <Input
                                        id={`slash-amount-${claimData.claimId}`}
                                        type="number"
                                        step="any"
                                        placeholder={`Max: ${formatUnits(claimData.claim.amount, tokenDecimals)}`}
                                        value={slashAmounts[claimData.claimId] || ""}
                                        onChange={(e) =>
                                            updateSlashAmount(claimData.claimId, e.target.value)
                                        }
                                        className="font-mono"
                                        disabled={isPending || isConfirming}
                                    />
                                    <div className="flex justify-end gap-2">
                                        <Button
                                            variant="ghost"
                                            size="sm"
                                            onClick={() =>
                                                updateSlashAmount(
                                                    claimData.claimId,
                                                    formatUnits(
                                                        claimData.claim.amount,
                                                        tokenDecimals
                                                    )
                                                )
                                            }
                                        >
                                            Max
                                        </Button>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </ScrollArea>

                <DialogFooter>
                    <Button
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        disabled={isPending || isConfirming}
                    >
                        Cancel
                    </Button>
                    <Button
                        variant="destructive"
                        onClick={handleSlash}
                        disabled={isPending || isConfirming || selectedClaims.length === 0}
                    >
                        {isPending || isConfirming ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <Zap className="mr-2 size-4" />
                        )}
                        {isPending
                            ? "Confirm in wallet..."
                            : isConfirming
                              ? "Slashing..."
                              : `Slash ${selectedClaims.length} Claim${selectedClaims.length > 1 ? "s" : ""}`}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}

/**
 * Coverage Claims Management component
 */
function CoverageClaimsManagement({
    contract,
    chainId,
    registeredProviders,
    savedContractsMap,
}: {
    contract: CoverageContract
    chainId: SupportedChainId | undefined
    registeredProviders: Address[]
    savedContractsMap: Map<string, CoverageContract>
}) {
    const config = useConfig()

    // Convert registered provider addresses to contracts for the select
    const registeredProviderContracts = useMemo(() => {
        return registeredProviders
            .map((addr) => {
                const key = `${contract.chainId}-${addr.toLowerCase()}`
                return savedContractsMap.get(key)
            })
            .filter((c): c is CoverageContract => c !== undefined)
    }, [registeredProviders, savedContractsMap, contract.chainId])

    // Form state for creating claims (store contract IDs)
    const [selectedProviderId, setSelectedProviderId] = useState("")
    const [positionId, setPositionId] = useState("")
    const [claimAmount, setClaimAmount] = useState("")
    const [claimDuration, setClaimDuration] = useState("30") // days
    const [claimReward, setClaimReward] = useState("")
    const [positionMaxAmount, setPositionMaxAmount] = useState<bigint | null>(null)
    const [isLoadingMaxAmount, setIsLoadingMaxAmount] = useState(false)
    const [isReservation, setIsReservation] = useState(false)

    // Claims viewing state
    const [loadedClaims, setLoadedClaims] = useState<LoadedClaimData[]>([])
    const [newClaimId, setNewClaimId] = useState("")
    const [loadClaimProviderId, setLoadClaimProviderId] = useState("")
    const [isLoadingClaim, setIsLoadingClaim] = useState(false)

    // Get selected provider addresses from contract IDs
    const selectedProvider = getSelectedProvider(selectedProviderId, registeredProviderContracts)
    const selectedProviderAddress = selectedProvider?.address ?? ""
    const loadClaimProviderContract = getSelectedProvider(
        loadClaimProviderId,
        registeredProviderContracts
    )
    const loadClaimProviderAddress = loadClaimProviderContract?.address ?? ""

    // Slashing state
    const [selectedClaimIds, setSelectedClaimIds] = useState<Set<number>>(new Set())
    const [slashDialogOpen, setSlashDialogOpen] = useState(false)

    // Token info
    const [tokenDecimals, setTokenDecimals] = useState(18)
    const [tokenSymbol, setTokenSymbol] = useState("TOKEN")

    // Get coverage agent asset
    const { data: assetAddress } = useReadContract({
        address: contract.address,
        abi: iCoverageAgentAbi,
        functionName: "asset",
        chainId,
        query: {
            enabled: !!chainId,
        },
    })

    // Fetch token details
    const { data: decimals } = useReadContract({
        address: assetAddress as Address,
        abi: ierc20Abi,
        functionName: "decimals",
        chainId,
        query: {
            enabled: !!assetAddress && !!chainId,
        },
    })

    const { data: symbol } = useReadContract({
        address: assetAddress as Address,
        abi: ierc20Abi,
        functionName: "symbol",
        chainId,
        query: {
            enabled: !!assetAddress && !!chainId,
        },
    })

    // Update token info when fetched
    useEffect(() => {
        if (decimals !== undefined) setTokenDecimals(Number(decimals))
        if (symbol) setTokenSymbol(symbol as string)
    }, [decimals, symbol])

    // Write contract hooks for claiming coverage
    const { writeContract, isPending, data: hash } = useWriteContract()
    const {
        isLoading: isConfirming,
        isSuccess,
        data: receipt,
    } = useWaitForTransactionReceipt({ hash })

    const prevCreateSuccessRef = useRef(false)

    // Load claim function wrapped in useCallback for use in effects
    const loadClaim = useCallback(
        async (claimId: number, providerAddress: string) => {
            if (!chainId) return

            setIsLoadingClaim(true)
            try {
                const [claim, backing, totalSlashAmount] = await Promise.all([
                    readContract(config, {
                        address: providerAddress as Address,
                        abi: iCoverageProviderAbi,
                        functionName: "claim",
                        args: [BigInt(claimId)],
                        chainId,
                    }),
                    readContract(config, {
                        address: providerAddress as Address,
                        abi: iCoverageProviderAbi,
                        functionName: "claimBacking",
                        args: [BigInt(claimId)],
                        chainId,
                    }),
                    readContract(config, {
                        address: providerAddress as Address,
                        abi: iCoverageProviderAbi,
                        functionName: "claimTotalSlashAmount",
                        args: [BigInt(claimId)],
                        chainId,
                    }),
                ])

                const claimData = claim as CoverageClaimData

                // Check if claim exists (has non-zero amount or duration)
                if (claimData.amount === 0n && claimData.duration === 0n) {
                    toast.error(`Claim #${claimId} does not exist`)
                    return
                }

                setLoadedClaims((prev) => {
                    // Check if claim already loaded
                    if (
                        prev.some(
                            (c) => c.claimId === claimId && c.providerAddress === providerAddress
                        )
                    ) {
                        return prev
                    }
                    return [
                        ...prev,
                        {
                            claimId,
                            providerAddress: providerAddress as Address,
                            claim: claimData,
                            backing: backing as bigint,
                            totalSlashAmount: totalSlashAmount as bigint,
                        },
                    ]
                })
                toast.success(`Claim #${claimId} loaded`)
            } catch {
                toast.error(`Failed to fetch claim #${claimId}`)
            } finally {
                setIsLoadingClaim(false)
            }
        },
        [chainId, config]
    )

    // Fetch max amount when provider and position are selected
    useEffect(() => {
        const fetchMaxAmount = async () => {
            if (!selectedProviderAddress || !positionId || !chainId) {
                setPositionMaxAmount(null)
                return
            }

            setIsLoadingMaxAmount(true)
            try {
                const maxAmount = await readContract(config, {
                    address: selectedProviderAddress as Address,
                    abi: iCoverageProviderAbi,
                    functionName: "positionMaxAmount",
                    args: [BigInt(positionId)],
                    chainId,
                })
                setPositionMaxAmount(maxAmount as bigint)
            } catch {
                setPositionMaxAmount(null)
                toast.error("Failed to fetch position max amount")
            } finally {
                setIsLoadingMaxAmount(false)
            }
        }

        fetchMaxAmount()
    }, [selectedProviderAddress, positionId, chainId, config])

    // Parse coverage ID from transaction logs when coverage is purchased successfully
    useEffect(() => {
        if (isSuccess && receipt && !prevCreateSuccessRef.current) {
            const loadCoverageClaimsAsync = async () => {
                try {
                    // Find the CoverageClaimed event in the logs
                    for (const log of receipt.logs) {
                        try {
                            const decoded = decodeEventLog({
                                abi: iCoverageAgentAbi,
                                data: log.data,
                                topics: log.topics,
                            })

                            if (
                                decoded.eventName === "CoverageClaimed" &&
                                decoded.args &&
                                "coverageId" in decoded.args
                            ) {
                                const coverageId = Number(decoded.args.coverageId)
                                toast.success(`Coverage #${coverageId} purchased successfully!`)

                                // Fetch the coverage to get the claims
                                if (chainId) {
                                    try {
                                        const coverageData = await readContract(config, {
                                            address: contract.address,
                                            abi: iCoverageAgentAbi,
                                            functionName: "coverage",
                                            args: [BigInt(coverageId)],
                                            chainId,
                                        })

                                        // Load each claim from the coverage
                                        const coverage = coverageData as {
                                            claims: Array<{
                                                coverageProvider: Address
                                                claimId: bigint
                                            }>,
                                            reservation: boolean
                                        }
                                        for (const claim of coverage.claims) {
                                            loadClaim(Number(claim.claimId), claim.coverageProvider)
                                        }
                                    } catch (error) {
                                        console.error("Error fetching coverage:", error)
                                    }
                                }
                                break
                            }
                        } catch {
                            // Not the event we're looking for, continue
                        }
                    }
                } catch (error) {
                    console.error("Error parsing coverage creation logs:", error)
                }
                // Reset form
                setPositionId("")
                setClaimAmount("")
                setClaimDuration("30")
                setClaimReward("")
                setPositionMaxAmount(null)
            }
            loadCoverageClaimsAsync()
        }
        prevCreateSuccessRef.current = isSuccess
    }, [isSuccess, receipt, loadClaim, chainId, config, contract.address])

    const handleAddClaim = async () => {
        const id = Number(newClaimId)
        if (isNaN(id) || id < 0) {
            toast.error("Please enter a valid claim ID")
            return
        }
        if (!loadClaimProviderAddress) {
            toast.error("Please select a coverage provider")
            return
        }
        await loadClaim(id, loadClaimProviderAddress)
        setNewClaimId("")
    }

    const handleRemoveClaim = (claimId: number, providerAddress: Address) => {
        setLoadedClaims((prev) =>
            prev.filter((c) => !(c.claimId === claimId && c.providerAddress === providerAddress))
        )
        setSelectedClaimIds((prev) => {
            const next = new Set(prev)
            next.delete(claimId)
            return next
        })
    }

    const handleToggleClaimSelection = (claimId: number, selected: boolean) => {
        setSelectedClaimIds((prev) => {
            const next = new Set(prev)
            if (selected) {
                next.add(claimId)
            } else {
                next.delete(claimId)
            }
            return next
        })
    }

    const handleCreateClaim = () => {
        if (
            !selectedProviderAddress ||
            !positionId ||
            !claimAmount ||
            !claimDuration ||
            !claimReward
        ) {
            toast.error("Please fill in all required fields")
            return
        }

        const amount = BigInt(Math.floor(parseFloat(claimAmount) * 10 ** tokenDecimals))
        const duration = BigInt(Number(claimDuration) * 24 * 60 * 60) // days to seconds
        const reward = BigInt(Math.floor(parseFloat(claimReward) * 10 ** tokenDecimals))

        // Create the ClaimCoverageRequest struct
        const request = {
            coverageProvider: selectedProviderAddress as Address,
            positionId: BigInt(positionId),
            amount,
            reward,
            duration,
        }

        // Use reserveCoverage if isReservation is true, otherwise use purchaseCoverage
        const successMessage = isReservation
            ? "Coverage reservation submitted"
            : "Coverage purchase submitted"

        writeContract(
            {
                address: contract.address,
                abi: exampleCoverageAgentAbi,
                functionName: isReservation ? "reserveCoverage" : "purchaseCoverage",
                args: [[request]],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`${successMessage}: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    toast.error(error.message.slice(0, 100))
                },
            }
        )
    }

    // Get selected claims for slashing - only from the same provider
    const selectedClaimsForSlash = useMemo(() => {
        const selectedClaims = loadedClaims.filter(
            (c) => selectedClaimIds.has(c.claimId) && c.claim.status === 0 // Only issued claims
        )
        // Group by provider - we can only slash claims from one provider at a time
        if (selectedClaims.length === 0) return []
        const firstProvider = selectedClaims[0].providerAddress
        return selectedClaims.filter((c) => c.providerAddress === firstProvider)
    }, [loadedClaims, selectedClaimIds])

    const handleSlashSuccess = () => {
        // Refresh claim data
        const claimIdsToRefresh = Array.from(selectedClaimIds)
        setSelectedClaimIds(new Set())
        // Reload the claims
        claimIdsToRefresh.forEach((claimId) => {
            const claimData = loadedClaims.find((c) => c.claimId === claimId)
            if (claimData) {
                handleRemoveClaim(claimId, claimData.providerAddress)
                loadClaim(claimId, claimData.providerAddress)
            }
        })
    }

    const isValidClaimForm = useMemo(() => {
        return (
            selectedProviderAddress &&
            positionId &&
            claimAmount &&
            parseFloat(claimAmount) > 0 &&
            claimDuration &&
            parseFloat(claimDuration) > 0 &&
            claimReward &&
            parseFloat(claimReward) >= 0 &&
            (positionMaxAmount === null ||
                BigInt(Math.floor(parseFloat(claimAmount) * 10 ** tokenDecimals)) <=
                    positionMaxAmount)
        )
    }, [
        selectedProviderAddress,
        positionId,
        claimAmount,
        claimDuration,
        claimReward,
        positionMaxAmount,
        tokenDecimals,
    ])

    return (
        <Card>
            <CardHeader>
                <div className="flex items-center justify-between">
                    <div>
                        <CardTitle className="flex items-center gap-2">
                            <Layers className="size-5" />
                            Coverage Claims Management
                        </CardTitle>
                        <CardDescription>
                            Create coverage claims and manage slashing
                        </CardDescription>
                    </div>
                </div>
            </CardHeader>
            <CardContent className="space-y-6">
                {/* Create Claim Section */}
                <div className="space-y-4">
                    <div className="rounded-lg bg-muted/50 p-3">
                        <h4 className="text-sm font-medium">Create New Coverage</h4>
                        <p className="text-xs text-muted-foreground mt-1">
                            {isReservation
                                ? "Reserve coverage without immediate payment (can be converted later)"
                                : "Purchase coverage from a registered provider position"}
                        </p>
                    </div>

                    {/* Reservation Toggle */}
                    <div className="flex items-center space-x-2">
                        <Checkbox
                            id="reservationMode"
                            checked={isReservation}
                            onChange={(e) => setIsReservation(e.target.checked)}
                            disabled={isPending || isConfirming}
                        />
                        <Label
                            htmlFor="reservationMode"
                            className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                        >
                            Reserve coverage (no immediate payment)
                        </Label>
                    </div>

                    <div className="space-y-2">
                        <Label>Coverage Provider</Label>
                        <CoverageProviderSelect
                            selectedContractId={selectedProviderId}
                            onSelectedContractIdChange={setSelectedProviderId}
                            contracts={registeredProviderContracts}
                            disabled={isPending || isConfirming}
                            placeholder="Select registered coverage provider..."
                            emptyMessage={
                                <>
                                    No coverage providers registered yet.
                                    <br />
                                    Register a coverage provider first.
                                </>
                            }
                        />
                        <p className="text-xs text-muted-foreground">
                            Select a coverage provider registered with this agent
                        </p>
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="positionId">Position ID</Label>
                        <Input
                            id="positionId"
                            type="number"
                            placeholder="Enter position ID..."
                            value={positionId}
                            onChange={(e) => setPositionId(e.target.value)}
                            className="font-mono"
                            disabled={isPending || isConfirming || !selectedProviderAddress}
                        />
                        {isLoadingMaxAmount && (
                            <p className="text-xs text-muted-foreground flex items-center gap-2">
                                <Loader2 className="size-3 animate-spin" />
                                Loading position max amount...
                            </p>
                        )}
                        {positionMaxAmount !== null && (
                            <p className="text-xs text-muted-foreground">
                                Max available:{" "}
                                <span className="font-mono">
                                    {formatUnits(positionMaxAmount, tokenDecimals)} {tokenSymbol}
                                </span>
                            </p>
                        )}
                    </div>

                    <div className="grid gap-4 md:grid-cols-3">
                        <div className="space-y-2">
                            <Label htmlFor="claimAmount">Amount ({tokenSymbol})</Label>
                            <Input
                                id="claimAmount"
                                type="number"
                                step="any"
                                placeholder="0.0"
                                value={claimAmount}
                                onChange={(e) => setClaimAmount(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming || !selectedProviderAddress}
                            />
                            {positionMaxAmount !== null &&
                                claimAmount &&
                                BigInt(Math.floor(parseFloat(claimAmount) * 10 ** tokenDecimals)) >
                                    positionMaxAmount && (
                                    <p className="text-xs text-destructive flex items-center gap-1">
                                        <AlertTriangle className="size-3" />
                                        Exceeds max amount
                                    </p>
                                )}
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="claimDuration">Duration (days)</Label>
                            <Input
                                id="claimDuration"
                                type="number"
                                placeholder="30"
                                value={claimDuration}
                                onChange={(e) => setClaimDuration(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming || !selectedProviderAddress}
                            />
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="claimReward">Reward ({tokenSymbol})</Label>
                            <Input
                                id="claimReward"
                                type="number"
                                step="any"
                                placeholder="0.0"
                                value={claimReward}
                                onChange={(e) => setClaimReward(e.target.value)}
                                className="font-mono"
                                disabled={isPending || isConfirming || !selectedProviderAddress}
                            />
                        </div>
                    </div>

                    <Button
                        onClick={handleCreateClaim}
                        disabled={!isValidClaimForm || isPending || isConfirming}
                        className="w-full"
                        variant={isReservation ? "outline" : "default"}
                    >
                        {isPending || isConfirming ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <Plus className="mr-2 size-4" />
                        )}
                        {isPending
                            ? "Confirm in wallet..."
                            : isConfirming
                              ? isReservation
                                  ? "Reserving..."
                                  : "Creating..."
                              : isReservation
                                ? "Reserve Coverage"
                                : "Purchase Coverage"}
                    </Button>

                    {isSuccess && (
                        <p className="flex items-center gap-2 text-sm text-green-600">
                            <CheckCircle2 className="size-4" />
                            {isReservation
                                ? "Coverage reserved successfully!"
                                : "Coverage purchased successfully!"}
                        </p>
                    )}
                </div>

                <Separator />

                {/* View Claims Section */}
                <div className="space-y-4">
                    <div className="flex items-center justify-between">
                        <h4 className="text-sm font-medium">View Claims</h4>
                        <div className="flex items-center gap-2">
                            <Badge variant="secondary">{loadedClaims.length} loaded</Badge>
                            {selectedClaimIds.size > 0 && (
                                <Badge variant="outline">{selectedClaimIds.size} selected</Badge>
                            )}
                        </div>
                    </div>

                    <div className="flex flex-col gap-2 sm:flex-row">
                        <div className="flex-1">
                            <CoverageProviderSelect
                                selectedContractId={loadClaimProviderId}
                                onSelectedContractIdChange={setLoadClaimProviderId}
                                contracts={registeredProviderContracts}
                                disabled={isLoadingClaim}
                                placeholder="Select registered coverage provider..."
                                emptyMessage={
                                    <>
                                        No coverage providers registered yet.
                                        <br />
                                        Register a coverage provider first.
                                    </>
                                }
                            />
                        </div>
                        <div className="flex gap-2 items-center">
                            <Input
                                placeholder="Claim ID..."
                                value={newClaimId}
                                onChange={(e) => setNewClaimId(e.target.value)}
                                className="font-mono w-32"
                                type="number"
                            />
                            <Button
                                variant="outline"
                                onClick={handleAddClaim}
                                disabled={
                                    !newClaimId ||
                                    !loadClaimProviderId ||
                                    isNaN(Number(newClaimId)) ||
                                    isLoadingClaim
                                }
                            >
                                {isLoadingClaim ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <Plus className="mr-2 size-4" />
                                )}
                                {isLoadingClaim ? "Loading..." : "Load"}
                            </Button>
                        </div>
                    </div>

                    {loadedClaims.length === 0 ? (
                        <div className="py-8 text-center text-sm text-muted-foreground">
                            Select a provider and enter a claim ID to view details
                        </div>
                    ) : (
                        <>
                            <ScrollArea className="h-fit">
                                <div className="space-y-3 max-h-[500px]">
                                    {loadedClaims.map((claimData) => (
                                        <ClaimItem
                                            key={`${claimData.providerAddress}-${claimData.claimId}`}
                                            claimData={claimData}
                                            isSelected={selectedClaimIds.has(claimData.claimId)}
                                            onSelect={(selected) =>
                                                handleToggleClaimSelection(
                                                    claimData.claimId,
                                                    selected
                                                )
                                            }
                                            onRemove={() =>
                                                handleRemoveClaim(
                                                    claimData.claimId,
                                                    claimData.providerAddress
                                                )
                                            }
                                            tokenDecimals={tokenDecimals}
                                            tokenSymbol={tokenSymbol}
                                        />
                                    ))}
                                </div>
                            </ScrollArea>

                            {/* Slash Button */}
                            {selectedClaimsForSlash.length > 0 && (
                                <div className="flex justify-end">
                                    <Button
                                        variant="destructive"
                                        onClick={() => setSlashDialogOpen(true)}
                                    >
                                        <Zap className="mr-2 size-4" />
                                        Slash {selectedClaimsForSlash.length} Claim
                                        {selectedClaimsForSlash.length > 1 ? "s" : ""}
                                    </Button>
                                </div>
                            )}
                        </>
                    )}
                </div>

                {/* Slash Dialog */}
                <SlashClaimsDialog
                    open={slashDialogOpen}
                    onOpenChange={setSlashDialogOpen}
                    selectedClaims={selectedClaimsForSlash}
                    providerAddress={
                        selectedClaimsForSlash[0]?.providerAddress || ("0x" as Address)
                    }
                    chainId={chainId}
                    tokenDecimals={tokenDecimals}
                    tokenSymbol={tokenSymbol}
                    onSuccess={handleSlashSuccess}
                />
            </CardContent>
        </Card>
    )
}

export function CoverageAgentInfo({ contract }: CoverageAgentInfoProps) {
    const { contracts } = useContracts()
    const [selectedProviderId, setSelectedProviderId] = useState<string>("")

    // Check if chainId is supported
    const isChainSupported = supportedChains.some((chain) => chain.id === contract.chainId)
    const supportedChainId = isChainSupported ? (contract.chainId as SupportedChainId) : undefined

    const {
        data: coverageProviders,
        isLoading,
        isError,
        refetch,
    } = useReadContract({
        address: contract.address,
        abi: iCoverageAgentAbi,
        functionName: "registeredCoverageProviders",
        chainId: supportedChainId,
        query: {
            enabled: isChainSupported,
        },
    })

    // Write contract hook for registering providers
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    // Track previous success state to detect new success
    const prevSuccessRef = useRef(false)

    // Refetch providers after successful registration
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            refetch()
            // Reset selection after successful registration
            // Using a timeout to avoid cascading renders
            const timeoutId = setTimeout(() => {
                setSelectedProviderId("")
            }, 0)
            return () => clearTimeout(timeoutId)
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, refetch])

    // Create a map of saved contracts by address for quick lookup
    const savedContractsMap = useMemo(() => {
        const map = new Map<string, CoverageContract>()
        contracts.forEach((c) => {
            const key = `${c.chainId}-${c.address.toLowerCase()}`
            map.set(key, c)
        })
        return map
    }, [contracts])

    // Registered provider addresses
    const registeredProviderAddresses = useMemo(() => {
        if (!coverageProviders) return []
        return coverageProviders as Address[]
    }, [coverageProviders])

    // Map registered provider addresses to saved contracts
    const registeredProviders = useMemo(() => {
        return registeredProviderAddresses
            .map((addr) => {
                const key = `${contract.chainId}-${addr.toLowerCase()}`
                return savedContractsMap.get(key)
            })
            .filter((c): c is CoverageContract => !!c)
    }, [registeredProviderAddresses, savedContractsMap, contract.chainId])

    // Extract IDs for exclusion
    const registeredProviderIds = useMemo(
        () => registeredProviders.map((p) => p.id),
        [registeredProviders]
    )

    // Get available providers (excluding already registered ones)
    const { availableProviders } = useAvailableCoverageProviders(
        contract.chainId,
        registeredProviderIds
    )

    // Get the selected provider contract
    const selectedProvider = getSelectedProvider(selectedProviderId, availableProviders)

    const handleRegisterProvider = () => {
        if (!selectedProvider) {
            toast.error("Please select a coverage provider")
            return
        }

        writeContract(
            {
                address: contract.address,
                abi: iCoverageAgentAbi,
                functionName: "registerCoverageProvider",
                args: [selectedProvider.address as `0x${string}`],
                chainId: supportedChainId,
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
        <div className="space-y-6">
            <Card>
                <CardHeader>
                    <div className="flex items-center justify-between">
                        <div>
                            <CardTitle>Registered Coverage Providers</CardTitle>
                            <CardDescription>
                                Coverage providers registered with this agent
                            </CardDescription>
                        </div>
                        <Button
                            variant="outline"
                            size="lg"
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
                <CardContent className="space-y-6">
                    {/* Registration Section */}
                    <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
                        <div className="flex-1">
                            <CoverageProviderSelect
                                selectedContractId={selectedProviderId}
                                onSelectedContractIdChange={setSelectedProviderId}
                                contracts={availableProviders}
                                disabled={isPending || isConfirming}
                            />
                        </div>
                        <Button
                            onClick={handleRegisterProvider}
                            disabled={
                                !selectedProvider ||
                                isPending ||
                                isConfirming ||
                                availableProviders.length === 0
                            }
                            size="lg"
                        >
                            {isPending || isConfirming ? (
                                <Loader2 className="mr-2 size-4 animate-spin" />
                            ) : (
                                <Plus className="mr-2 size-4" />
                            )}
                            {isPending
                                ? "Confirming..."
                                : isConfirming
                                  ? "Registering..."
                                  : "Register"}
                        </Button>
                    </div>

                    {isSuccess && (
                        <p className="flex items-center gap-2 text-sm text-green-600">
                            <CheckCircle2 className="size-4" />
                            Coverage provider registered successfully!
                        </p>
                    )}

                    {/* Providers List */}
                    {isLoading && registeredProviders.length === 0 ? (
                        <div className="flex items-center justify-center py-8">
                            <Loader2 className="size-6 animate-spin text-muted-foreground" />
                        </div>
                    ) : isError ? (
                        <div className="py-8 text-center text-sm text-destructive">
                            Failed to fetch coverage providers
                        </div>
                    ) : registeredProviders.length === 0 ? (
                        <div className="py-8 text-center text-sm text-muted-foreground">
                            No coverage providers registered yet
                        </div>
                    ) : (
                        <ScrollArea className="h-fit max-h-[400px]">
                            <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
                                {registeredProviders.map((provider) => (
                                    <ContractCard key={provider.id} contract={provider} />
                                ))}
                            </div>
                        </ScrollArea>
                    )}
                </CardContent>
            </Card>

            {/* Coverage Claims Management */}
            <CoverageClaimsManagement
                contract={contract}
                chainId={supportedChainId}
                registeredProviders={registeredProviderAddresses}
                savedContractsMap={savedContractsMap}
            />
        </div>
    )
}
