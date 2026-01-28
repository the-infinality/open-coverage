import { useMemo, useState, useEffect, useRef, useCallback } from "react"
import { type Address, type Abi, formatUnits, decodeEventLog, decodeErrorResult, BaseError } from "viem"
import {
    RefreshCw,
    Loader2,
    Plus,
    CheckCircle2,
    Layers,
    Zap,
    Trash2,
    AlertTriangle,
    ArrowRightLeft,
    X,
} from "lucide-react"
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useConfig, useAccount } from "wagmi"
import { readContract } from "wagmi/actions"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { iCoverageAgentAbi, iCoverageProviderAbi, iExampleCoverageAgentAbi } from "@/generated/abis"
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
import { WalletRequirement } from "@/components/WalletRequirement"

type SupportedChainId = (typeof supportedChains)[number]["id"]

// Combined ABI for error decoding
const combinedErrorAbi = [
    // ICoverageProvider errors
    { type: "error", inputs: [{ name: "claimId", type: "uint256" }, { name: "amount", type: "uint256" }, { name: "reserved", type: "uint256" }], name: "AmountExceedsReserved" },
    { type: "error", inputs: [{ name: "claimId", type: "uint256" }], name: "ClaimNotExpired" },
    { type: "error", inputs: [{ name: "claimId", type: "uint256" }], name: "ClaimNotReserved" },
    { type: "error", inputs: [{ name: "expiryTimestamp", type: "uint256" }, { name: "completionTimestamp", type: "uint256" }], name: "DurationExceedsExpiry" },
    { type: "error", inputs: [{ name: "maxDuration", type: "uint256" }, { name: "duration", type: "uint256" }], name: "DurationExceedsMax" },
    { type: "error", inputs: [{ name: "deficit", type: "uint256" }], name: "InsufficientCoverageAvailable" },
    { type: "error", inputs: [{ name: "minimumReward", type: "uint256" }, { name: "reward", type: "uint256" }], name: "InsufficientReward" },
    { type: "error", inputs: [], name: "InvalidAmount" },
    { type: "error", inputs: [{ name: "claimId", type: "uint256" }], name: "InvalidClaim" },
    { type: "error", inputs: [{ name: "minRate", type: "uint16" }], name: "MinRateInvalid" },
    { type: "error", inputs: [{ name: "caller", type: "address" }, { name: "required", type: "address" }], name: "NotCoverageAgent" },
    { type: "error", inputs: [{ name: "positionId", type: "uint256" }], name: "PositionExpired" },
    { type: "error", inputs: [{ name: "claimId", type: "uint256" }], name: "ReservationExpired" },
    { type: "error", inputs: [{ name: "positionId", type: "uint256" }], name: "ReservationNotAllowed" },
    { type: "error", inputs: [], name: "RewardTransferFailed" },
    // ICoverageAgent errors
    { type: "error", inputs: [], name: "CoverageProviderAlreadyRegistered" },
    { type: "error", inputs: [], name: "CoverageProviderNotRegistered" },
    { type: "error", inputs: [], name: "InvalidClaimStatus" },
    { type: "error", inputs: [], name: "SlashAmountExceedsClaimAmount" },
    { type: "error", inputs: [], name: "ClaimAlreadySlashed" },
    { type: "error", inputs: [], name: "ClaimNotActive" },
    // Diamond errors
    { type: "error", inputs: [], name: "NotContractOwner" },
    // Common errors
    { type: "error", inputs: [], name: "ZeroAddress" },
] as const

// Human-readable error messages
const errorMessages: Record<string, string> = {
    AmountExceedsReserved: "Amount exceeds the reserved amount for this claim.",
    ClaimNotExpired: "Claim has not expired yet.",
    ClaimNotReserved: "Claim is not in reserved state.",
    DurationExceedsExpiry: "The coverage duration would exceed the position expiry.",
    DurationExceedsMax: "The requested duration exceeds the maximum allowed.",
    InsufficientCoverageAvailable: "Not enough coverage available. The operator may not have sufficient allocation.",
    InsufficientReward: "The reward amount is less than the minimum required for this coverage.",
    InvalidAmount: "Invalid amount specified.",
    InvalidClaim: "The claim does not exist or is invalid.",
    MinRateInvalid: "The minimum rate is invalid.",
    NotCoverageAgent: "Only the coverage agent can perform this action.",
    PositionExpired: "The position has expired.",
    ReservationExpired: "The reservation has expired.",
    ReservationNotAllowed: "Reservations are not allowed for this position.",
    RewardTransferFailed: "Failed to transfer the reward.",
    CoverageProviderAlreadyRegistered: "This coverage provider is already registered.",
    CoverageProviderNotRegistered: "This coverage provider is not registered.",
    InvalidClaimStatus: "Invalid claim status for this operation.",
    SlashAmountExceedsClaimAmount: "Slash amount exceeds the claim amount.",
    ClaimAlreadySlashed: "This claim has already been slashed.",
    ClaimNotActive: "The claim is not active.",
    NotContractOwner: "Only the contract owner can perform this action.",
    ZeroAddress: "Cannot use zero address.",
}

/**
 * Decodes a contract error and returns a human-readable message
 */
function decodeContractError(error: unknown): string {
    if (error instanceof BaseError) {
        let currentError: unknown = error
        while (currentError) {
            if (
                typeof currentError === "object" &&
                currentError !== null &&
                "data" in currentError &&
                typeof (currentError as { data?: unknown }).data === "string"
            ) {
                const errorData = (currentError as { data: string }).data
                if (errorData && errorData.startsWith("0x") && errorData.length >= 10) {
                    try {
                        const decoded = decodeErrorResult({
                            abi: combinedErrorAbi as Abi,
                            data: errorData as `0x${string}`,
                        })
                        
                        const friendlyMessage = errorMessages[decoded.errorName]
                        if (friendlyMessage) {
                            if (decoded.args && decoded.args.length > 0) {
                                return `${friendlyMessage} (${decoded.args.join(", ")})`
                            }
                            return friendlyMessage
                        }
                        return `Contract error: ${decoded.errorName}`
                    } catch {
                        // Could not decode, continue
                    }
                }
            }
            currentError =
                typeof currentError === "object" && currentError !== null && "cause" in currentError
                    ? (currentError as { cause?: unknown }).cause
                    : null
        }
        
        const errorMessage = error.message || ""
        const revertMatch = errorMessage.match(/reverted with reason string '([^']+)'/)
        if (revertMatch) return revertMatch[1]
        
        const customErrorMatch = errorMessage.match(/reverted with custom error '([^'(]+)/)
        if (customErrorMatch) {
            const errorName = customErrorMatch[1]
            return errorMessages[errorName] || `Contract error: ${errorName}`
        }
        
        for (const [errorName, message] of Object.entries(errorMessages)) {
            if (errorMessage.includes(errorName)) return message
        }
    }
    
    const message = error instanceof Error ? error.message : String(error)
    return message.length > 200 ? message.slice(0, 200) + "..." : message
}

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
    coverageId: number
}

interface PendingCoverageRequest {
    id: string // unique id for the request
    providerAddress: Address
    providerName: string
    positionId: bigint
    amount: bigint
    duration: bigint
    reward: bigint
}

/**
 * Claim Item component for displaying individual claims
 */
function ClaimItem({
    claimData,
    tokenDecimals,
    tokenSymbol,
    totalSlashAmount,
}: {
    claimData: LoadedClaimData
    tokenDecimals: number
    totalSlashAmount: bigint
    tokenSymbol: string
}) {
    const { claim, claimId, providerAddress, backing } = claimData
    const statusInfo = CLAIM_STATUS_LABELS[claim.status] || {
        label: "Unknown",
        variant: "outline" as const,
    }
    const isExpired =
        BigInt(claim.createdAt) + BigInt(claim.duration) < BigInt(Math.floor(Date.now() / 1000))
    const expiryDate = new Date(Number(claim.createdAt + claim.duration) * 1000)
    const createdDate = new Date(Number(claim.createdAt) * 1000)

    return (
        <div className="rounded-lg border p-4 space-y-3">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <Badge variant="outline">Claim #{claimId}</Badge>
                    <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>
                    {isExpired && <Badge variant="destructive">Expired</Badge>}
                </div>
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
/**
 * Slash Coverage Dialog - slashes all claims in a coverage via the CoverageAgent
 */
function SlashCoverageDialog({
    open,
    onOpenChange,
    coverageId,
    claims,
    contractAddress,
    chainId,
    tokenDecimals,
    tokenSymbol,
    onSuccess,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    coverageId: number | null
    claims: LoadedClaimData[]
    contractAddress: Address
    chainId: SupportedChainId | undefined
    tokenDecimals: number
    tokenSymbol: string
    onSuccess: () => void
}) {
    const { writeContract, isPending, data: hash } = useWriteContract()
    const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } = useWaitForTransactionReceipt({ hash })

    const prevSuccessRef = useRef(false)
    const hasShownReceiptError = useRef<string>("")

    // Calculate total slash amount
    const totalAmount = useMemo(() => {
        return claims.reduce((sum, c) => sum + c.claim.amount, 0n)
    }, [claims])

    // Handle success
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            toast.success("Coverage slashed successfully!")
            onSuccess()
            onOpenChange(false)
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, onSuccess, onOpenChange])

    // Handle transaction receipt errors
    useEffect(() => {
        if (isReceiptError && receiptError && hash && hasShownReceiptError.current !== hash) {
            hasShownReceiptError.current = hash
            const decodedError = decodeContractError(receiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
        }
    }, [isReceiptError, receiptError, hash])

    const handleSlash = () => {
        if (coverageId === null) return

        writeContract(
            {
                address: contractAddress,
                abi: iExampleCoverageAgentAbi,
                functionName: "slashCoverage",
                args: [BigInt(coverageId)],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Slash transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    if (coverageId === null) return null

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="sm:max-w-lg">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                        <Zap className="size-5 text-destructive" />
                        Slash Coverage #{coverageId}
                    </DialogTitle>
                    <DialogDescription>
                        This will slash all claims in this coverage. The slash amounts will be
                        the full claim amounts for each claim.
                    </DialogDescription>
                </DialogHeader>

                <div className="space-y-4">
                    {/* Summary */}
                    <div className="rounded-lg border bg-destructive/10 p-4 space-y-2">
                        <div className="flex items-center justify-between text-sm">
                            <span className="text-muted-foreground">Total Claims</span>
                            <span className="font-medium">{claims.length}</span>
                        </div>
                        <div className="flex items-center justify-between text-sm">
                            <span className="text-muted-foreground">Total Slash Amount</span>
                            <span className="font-mono font-medium text-destructive">
                                {formatUnits(totalAmount, tokenDecimals)} {tokenSymbol}
                            </span>
                        </div>
                    </div>

                    {/* Claims List */}
                    <div className="space-y-2">
                        <h4 className="text-sm font-medium">Claims to be slashed:</h4>
                        <ScrollArea className="max-h-[200px]">
                            <div className="space-y-2">
                                {claims.map((claimData) => (
                                    <div
                                        key={`${claimData.providerAddress}-${claimData.claimId}`}
                                        className="flex items-center justify-between rounded-md border bg-muted/30 p-2 text-sm"
                                    >
                                        <div className="flex items-center gap-2">
                                            <Badge variant="outline" className="font-mono text-xs">
                                                Claim #{claimData.claimId}
                                            </Badge>
                                            <span className="text-xs text-muted-foreground">
                                                Position {claimData.claim.positionId.toString()}
                                            </span>
                                        </div>
                                        <span className="font-mono text-destructive">
                                            {formatUnits(claimData.claim.amount, tokenDecimals)} {tokenSymbol}
                                        </span>
                                    </div>
                                ))}
                            </div>
                        </ScrollArea>
                    </div>
                </div>

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
                        disabled={isPending || isConfirming || claims.length === 0}
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
                              : "Slash Coverage"}
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    )
}

/**
 * Convert Coverage Dialog
 */
function ConvertCoverageDialog({
    open,
    onOpenChange,
    coverageId,
    claims,
    contractAddress,
    assetAddress,
    chainId,
    tokenDecimals,
    tokenSymbol,
    onSuccess,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    coverageId: number | null
    claims: LoadedClaimData[]
    contractAddress: Address
    assetAddress: Address | undefined
    chainId: SupportedChainId | undefined
    tokenDecimals: number
    tokenSymbol: string
    onSuccess: () => void
}) {
    const { address: userAddress } = useAccount()
    const [convertAmounts, setConvertAmounts] = useState<Record<number, string>>({})
    const [convertDurations, setConvertDurations] = useState<Record<number, string>>({})
    const [convertRewards, setConvertRewards] = useState<Record<number, string>>({})
    const [isApproving, setIsApproving] = useState(false)
    
    const { writeContract, isPending, data: hash, reset: resetWrite } = useWriteContract()
    const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } = useWaitForTransactionReceipt({ hash })

    // Fetch user's token balance
    const { data: userBalance } = useReadContract({
        address: assetAddress,
        abi: ierc20Abi,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
        chainId,
        query: {
            enabled: !!assetAddress && !!userAddress && !!chainId && open,
        },
    })

    // Fetch current allowance
    const { data: currentAllowance, refetch: refetchAllowance } = useReadContract({
        address: assetAddress,
        abi: ierc20Abi,
        functionName: "allowance",
        args: userAddress ? [userAddress, contractAddress] : undefined,
        chainId,
        query: {
            enabled: !!assetAddress && !!userAddress && !!chainId && open,
        },
    })

    const prevSuccessRef = useRef(false)
    const hasShownReceiptError = useRef<string>("")

    // Calculate total reward from form inputs
    const totalReward = useMemo(() => {
        let total = 0n
        for (const claim of claims) {
            const rewardStr = convertRewards[claim.claimId]
            if (rewardStr && parseFloat(rewardStr) > 0) {
                total += BigInt(Math.floor(parseFloat(rewardStr) * 10 ** tokenDecimals))
            }
        }
        return total
    }, [claims, convertRewards, tokenDecimals])

    // Check if approval is needed
    const needsApproval = useMemo(() => {
        if (!currentAllowance) return true
        return (currentAllowance as bigint) < totalReward
    }, [currentAllowance, totalReward])

    // Check if user has sufficient balance
    const hasSufficientBalance = useMemo(() => {
        if (!userBalance) return false
        return (userBalance as bigint) >= totalReward
    }, [userBalance, totalReward])

    // Initialize amounts when claims change
    useEffect(() => {
        const initialAmounts: Record<number, string> = {}
        const initialDurations: Record<number, string> = {}
        const initialRewards: Record<number, string> = {}
        claims.forEach((c) => {
            initialAmounts[c.claimId] = formatUnits(c.claim.amount, tokenDecimals)
            initialDurations[c.claimId] = Math.round(Number(c.claim.duration) / 86400).toString()
            initialRewards[c.claimId] = formatUnits(c.claim.reward, tokenDecimals)
        })
        setConvertAmounts(initialAmounts)
        setConvertDurations(initialDurations)
        setConvertRewards(initialRewards)
    }, [claims, tokenDecimals])

    // Handle success - either approval or convert
    useEffect(() => {
        if (isSuccess && !prevSuccessRef.current) {
            if (isApproving) {
                toast.success("Approval successful! You can now convert.")
                setIsApproving(false)
                resetWrite()
                // Refetch allowance after approval
                refetchAllowance()
            } else {
                toast.success("Coverage converted successfully!")
                onSuccess()
                onOpenChange(false)
            }
        }
        prevSuccessRef.current = isSuccess
    }, [isSuccess, isApproving, onSuccess, onOpenChange, refetchAllowance, resetWrite])

    // Handle transaction receipt errors
    useEffect(() => {
        if (isReceiptError && receiptError && hash && hasShownReceiptError.current !== hash) {
            hasShownReceiptError.current = hash
            const decodedError = decodeContractError(receiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
            setIsApproving(false)
        }
    }, [isReceiptError, receiptError, hash])

    // Reset state when dialog closes
    useEffect(() => {
        if (!open) {
            setIsApproving(false)
            prevSuccessRef.current = false
            hasShownReceiptError.current = ""
        }
    }, [open])

    const handleApprove = () => {
        if (!assetAddress) return

        setIsApproving(true)
        writeContract(
            {
                address: assetAddress,
                abi: ierc20Abi,
                functionName: "approve",
                args: [contractAddress, totalReward],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Approval submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    setIsApproving(false)
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    const handleConvert = () => {
        if (coverageId === null) return

        // Check balance first
        if (!hasSufficientBalance) {
            toast.error("Insufficient balance to pay the total reward")
            return
        }

        // Check allowance
        if (needsApproval) {
            toast.error("Please approve the token transfer first")
            return
        }

        const requests: Array<{
            coverageProvider: Address
            positionId: bigint
            amount: bigint
            duration: bigint
            reward: bigint
        }> = []

        for (const claim of claims) {
            const amountStr = convertAmounts[claim.claimId]
            const durationStr = convertDurations[claim.claimId]
            const rewardStr = convertRewards[claim.claimId]

            if (!amountStr || parseFloat(amountStr) <= 0) {
                toast.error(`Please enter a valid amount for claim #${claim.claimId}`)
                return
            }
            if (!durationStr || parseFloat(durationStr) <= 0) {
                toast.error(`Please enter a valid duration for claim #${claim.claimId}`)
                return
            }
            if (!rewardStr || parseFloat(rewardStr) < 0) {
                toast.error(`Please enter a valid reward for claim #${claim.claimId}`)
                return
            }

            const amount = BigInt(Math.floor(parseFloat(amountStr) * 10 ** tokenDecimals))
            const duration = BigInt(Math.floor(parseFloat(durationStr) * 86400)) // days to seconds
            const reward = BigInt(Math.floor(parseFloat(rewardStr) * 10 ** tokenDecimals))

            // Check amount doesn't exceed reserved
            if (amount > claim.claim.amount) {
                toast.error(`Amount for claim #${claim.claimId} exceeds reserved amount`)
                return
            }

            // Check duration doesn't exceed reserved
            if (duration > claim.claim.duration) {
                toast.error(`Duration for claim #${claim.claimId} exceeds reserved duration`)
                return
            }

            requests.push({
                coverageProvider: claim.providerAddress,
                positionId: claim.claim.positionId,
                amount,
                duration,
                reward,
            })
        }

        writeContract(
            {
                address: contractAddress,
                abi: iExampleCoverageAgentAbi,
                functionName: "convertReservedCoverage",
                args: [BigInt(coverageId), requests],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Transaction submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    const updateAmount = (claimId: number, value: string) => {
        setConvertAmounts((prev) => ({ ...prev, [claimId]: value }))
    }

    const updateDuration = (claimId: number, value: string) => {
        setConvertDurations((prev) => ({ ...prev, [claimId]: value }))
    }

    const updateReward = (claimId: number, value: string) => {
        setConvertRewards((prev) => ({ ...prev, [claimId]: value }))
    }

    if (coverageId === null) return null

    const isProcessing = isPending || isConfirming

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="sm:max-w-2xl">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                        <ArrowRightLeft className="size-5 text-primary" />
                        Convert Reserved Coverage #{coverageId}
                    </DialogTitle>
                    <DialogDescription>
                        Convert your reserved coverage to issued coverage. You can adjust the amount,
                        duration, and reward for each claim (must be less than or equal to reserved values).
                    </DialogDescription>
                </DialogHeader>

                {/* Balance and Allowance Info */}
                <div className="rounded-lg border bg-muted/50 p-3 space-y-2">
                    <div className="grid gap-2 text-sm">
                        <div className="flex items-center justify-between">
                            <span className="text-muted-foreground">Your Balance</span>
                            <span className={`font-mono ${!hasSufficientBalance && totalReward > 0n ? "text-destructive" : ""}`}>
                                {userBalance !== undefined
                                    ? `${formatUnits(userBalance as bigint, tokenDecimals)} ${tokenSymbol}`
                                    : "Loading..."}
                            </span>
                        </div>
                        <div className="flex items-center justify-between">
                            <span className="text-muted-foreground">Current Allowance</span>
                            <span className={`font-mono ${needsApproval && totalReward > 0n ? "text-amber-600" : "text-green-600"}`}>
                                {currentAllowance !== undefined
                                    ? `${formatUnits(currentAllowance as bigint, tokenDecimals)} ${tokenSymbol}`
                                    : "Loading..."}
                            </span>
                        </div>
                        <Separator />
                        <div className="flex items-center justify-between font-medium">
                            <span>Total Reward Required</span>
                            <span className="font-mono">
                                {formatUnits(totalReward, tokenDecimals)} {tokenSymbol}
                            </span>
                        </div>
                    </div>

                    {/* Warning messages */}
                    {!hasSufficientBalance && totalReward > 0n && (
                        <div className="flex items-center gap-2 text-sm text-destructive mt-2">
                            <AlertTriangle className="size-4" />
                            <span>Insufficient balance to pay the total reward</span>
                        </div>
                    )}
                    {hasSufficientBalance && needsApproval && totalReward > 0n && (
                        <div className="flex items-center gap-2 text-sm text-amber-600 mt-2">
                            <AlertTriangle className="size-4" />
                            <span>Token approval required before converting</span>
                        </div>
                    )}
                    {hasSufficientBalance && !needsApproval && totalReward > 0n && (
                        <div className="flex items-center gap-2 text-sm text-green-600 mt-2">
                            <CheckCircle2 className="size-4" />
                            <span>Sufficient balance and allowance</span>
                        </div>
                    )}
                </div>

                <ScrollArea className="max-h-[350px]">
                    <div className="space-y-4">
                        {claims.map((claimData) => (
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
                                        <span className="text-muted-foreground">Reserved Amount</span>
                                        <span className="font-mono">
                                            {formatUnits(claimData.claim.amount, tokenDecimals)}{" "}
                                            {tokenSymbol}
                                        </span>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Reserved Duration</span>
                                        <span className="font-mono">
                                            {Math.round(Number(claimData.claim.duration) / 86400)} days
                                        </span>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">Reserved Reward</span>
                                        <span className="font-mono">
                                            {formatUnits(claimData.claim.reward, tokenDecimals)}{" "}
                                            {tokenSymbol}
                                        </span>
                                    </div>
                                </div>

                                <Separator />

                                <div className="grid gap-3 md:grid-cols-3">
                                    <div className="space-y-2">
                                        <Label htmlFor={`convert-amount-${claimData.claimId}`}>
                                            Amount ({tokenSymbol})
                                        </Label>
                                        <Input
                                            id={`convert-amount-${claimData.claimId}`}
                                            type="number"
                                            step="any"
                                            placeholder={`Max: ${formatUnits(claimData.claim.amount, tokenDecimals)}`}
                                            value={convertAmounts[claimData.claimId] || ""}
                                            onChange={(e) =>
                                                updateAmount(claimData.claimId, e.target.value)
                                            }
                                            className="font-mono"
                                            disabled={isProcessing}
                                        />
                                    </div>

                                    <div className="space-y-2">
                                        <Label htmlFor={`convert-duration-${claimData.claimId}`}>
                                            Duration (days)
                                        </Label>
                                        <Input
                                            id={`convert-duration-${claimData.claimId}`}
                                            type="number"
                                            placeholder={`Max: ${Math.round(Number(claimData.claim.duration) / 86400)}`}
                                            value={convertDurations[claimData.claimId] || ""}
                                            onChange={(e) =>
                                                updateDuration(claimData.claimId, e.target.value)
                                            }
                                            className="font-mono"
                                            disabled={isProcessing}
                                        />
                                    </div>

                                    <div className="space-y-2">
                                        <Label htmlFor={`convert-reward-${claimData.claimId}`}>
                                            Reward ({tokenSymbol})
                                        </Label>
                                        <Input
                                            id={`convert-reward-${claimData.claimId}`}
                                            type="number"
                                            step="any"
                                            placeholder="Enter reward..."
                                            value={convertRewards[claimData.claimId] || ""}
                                            onChange={(e) =>
                                                updateReward(claimData.claimId, e.target.value)
                                            }
                                            className="font-mono"
                                            disabled={isProcessing}
                                        />
                                    </div>
                                </div>

                                <div className="flex justify-end gap-2">
                                    <Button
                                        variant="ghost"
                                        size="sm"
                                        onClick={() => {
                                            updateAmount(
                                                claimData.claimId,
                                                formatUnits(claimData.claim.amount, tokenDecimals)
                                            )
                                            updateDuration(
                                                claimData.claimId,
                                                Math.round(Number(claimData.claim.duration) / 86400).toString()
                                            )
                                            updateReward(
                                                claimData.claimId,
                                                formatUnits(claimData.claim.reward, tokenDecimals)
                                            )
                                        }}
                                        disabled={isProcessing}
                                    >
                                        Use Reserved Values
                                    </Button>
                                </div>
                            </div>
                        ))}
                    </div>
                </ScrollArea>

                <DialogFooter className="flex-col sm:flex-row gap-2">
                    <Button
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        disabled={isProcessing}
                    >
                        Cancel
                    </Button>
                    
                    {/* Approve Button - show when approval is needed */}
                    {needsApproval && totalReward > 0n && (
                        <Button
                            variant="secondary"
                            onClick={handleApprove}
                            disabled={isProcessing || !hasSufficientBalance || claims.length === 0}
                        >
                            {isProcessing && isApproving ? (
                                <Loader2 className="mr-2 size-4 animate-spin" />
                            ) : (
                                <CheckCircle2 className="mr-2 size-4" />
                            )}
                            {isProcessing && isApproving
                                ? isPending
                                    ? "Confirm in wallet..."
                                    : "Approving..."
                                : `Approve ${formatUnits(totalReward, tokenDecimals)} ${tokenSymbol}`}
                        </Button>
                    )}

                    {/* Convert Button */}
                    <Button
                        onClick={handleConvert}
                        disabled={isProcessing || claims.length === 0 || needsApproval || !hasSufficientBalance || totalReward === 0n}
                    >
                        {isProcessing && !isApproving ? (
                            <Loader2 className="mr-2 size-4 animate-spin" />
                        ) : (
                            <ArrowRightLeft className="mr-2 size-4" />
                        )}
                        {isProcessing && !isApproving
                            ? isPending
                                ? "Confirm in wallet..."
                                : "Converting..."
                            : "Convert Coverage"}
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
    const { address: userAddress } = useAccount()

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

    // Pending coverage requests (multi-position support)
    const [pendingRequests, setPendingRequests] = useState<PendingCoverageRequest[]>([])

    // Coverage viewing state
    const [loadedClaims, setLoadedClaims] = useState<LoadedClaimData[]>([])
    const [newCoverageId, setNewCoverageId] = useState("")
    const [isLoadingCoverage, setIsLoadingCoverage] = useState(false)
    const [loadedCoverageIds, setLoadedCoverageIds] = useState<Set<number>>(new Set())
    const [reservationCoverageIds, setReservationCoverageIds] = useState<Set<number>>(new Set())

    // Convert coverage dialog state
    const [convertDialogOpen, setConvertDialogOpen] = useState(false)
    const [convertCoverageId, setConvertCoverageId] = useState<number | null>(null)

    // Slash coverage dialog state
    const [slashDialogOpen, setSlashDialogOpen] = useState(false)
    const [slashCoverageId, setSlashCoverageId] = useState<number | null>(null)

    // Get selected provider addresses from contract IDs
    const selectedProvider = getSelectedProvider(selectedProviderId, registeredProviderContracts)
    const selectedProviderAddress = selectedProvider?.address ?? ""

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

    // Fetch user's token balance for purchase
    const { data: userBalance } = useReadContract({
        address: assetAddress as Address,
        abi: ierc20Abi,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
        chainId,
        query: {
            enabled: !!assetAddress && !!userAddress && !!chainId,
        },
    })

    // Fetch current allowance for purchase
    const { data: currentAllowance, refetch: refetchAllowance } = useReadContract({
        address: assetAddress as Address,
        abi: ierc20Abi,
        functionName: "allowance",
        args: userAddress ? [userAddress, contract.address] : undefined,
        chainId,
        query: {
            enabled: !!assetAddress && !!userAddress && !!chainId,
        },
    })

    // Calculate total reward amount from all pending requests
    const totalPendingReward = useMemo(() => {
        return pendingRequests.reduce((sum, req) => sum + req.reward, 0n)
    }, [pendingRequests])

    // Check if approval is needed for pending list purchase (only when not a reservation)
    const purchaseNeedsApproval = useMemo(() => {
        if (isReservation) return false // Reservations don't need approval
        if (pendingRequests.length === 0) return false
        if (!currentAllowance) return true
        return (currentAllowance as bigint) < totalPendingReward
    }, [currentAllowance, totalPendingReward, isReservation, pendingRequests.length])

    // Check if user has sufficient balance for pending list purchase
    const purchaseHasSufficientBalance = useMemo(() => {
        if (isReservation) return true // Reservations don't need balance
        if (pendingRequests.length === 0) return true
        if (!userBalance) return false
        return (userBalance as bigint) >= totalPendingReward
    }, [userBalance, totalPendingReward, isReservation, pendingRequests.length])

    // Approval state for purchase
    const [isApprovingPurchase, setIsApprovingPurchase] = useState(false)

    // Write contract hooks for claiming coverage
    const { writeContract, isPending, data: hash, reset: resetPurchaseWrite } = useWriteContract()
    const {
        isLoading: isConfirming,
        isSuccess,
        data: receipt,
        isError: isReceiptError,
        error: receiptError,
    } = useWaitForTransactionReceipt({ hash })

    const prevCreateSuccessRef = useRef(false)
    const hasShownReceiptError = useRef<string>("")

    // Handle transaction receipt errors (transaction was mined but reverted)
    useEffect(() => {
        if (isReceiptError && receiptError && hash && hasShownReceiptError.current !== hash) {
            hasShownReceiptError.current = hash
            const decodedError = decodeContractError(receiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
            setIsApprovingPurchase(false)
        }
    }, [isReceiptError, receiptError, hash])

    // Load a single claim from a provider
    const loadClaim = useCallback(
        async (claimId: number, providerAddress: string, coverageId: number): Promise<boolean> => {
            console.log(claimId, providerAddress, coverageId, chainId)
            if (!chainId) return false

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
                console.log(claim, backing)

                const claimData = claim as CoverageClaimData

                // Check if claim exists (createdAt would be 0 for non-existent claims)
                if (claimData.createdAt === 0n) {
                    return false
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
                            coverageId,
                        },
                    ]
                })
                return true
            } catch (error) {
                console.error("Error loading claim:", error)
                toast.error(`Failed to load claim #${claimId}`)
                return false
            }
        },
        [chainId, config]
    )

    // Load coverage and all its claims
    const loadCoverage = useCallback(
        async (coverageId: number) => {
            if (!chainId) return

            // Check if already loaded
            if (loadedCoverageIds.has(coverageId)) {
                toast.error(`Coverage #${coverageId} is already loaded`)
                return
            }

            setIsLoadingCoverage(true)
            try {
                const coverageData = await readContract(config, {
                    address: contract.address,
                    abi: iCoverageAgentAbi,
                    functionName: "coverage",
                    args: [BigInt(coverageId)],
                    chainId,
                })

                const coverage = coverageData as {
                    claims: Array<{
                        coverageProvider: Address
                        claimId: bigint
                    }>
                    reservation: boolean
                }

                if (!coverage.claims || coverage.claims.length === 0) {
                    toast.error(`Coverage #${coverageId} has no claims or does not exist`)
                    return
                }

                // Load all claims from this coverage
                let loadedCount = 0
                for (const claim of coverage.claims) {
                    const success = await loadClaim(
                        Number(claim.claimId),
                        claim.coverageProvider,
                        coverageId
                    )
                    if (success) loadedCount++
                }

                if (loadedCount > 0) {
                    setLoadedCoverageIds((prev) => new Set([...prev, coverageId]))
                    // Track if this coverage is a reservation
                    if (coverage.reservation) {
                        setReservationCoverageIds((prev) => new Set([...prev, coverageId]))
                    }
                    toast.success(
                        `Coverage #${coverageId} loaded with ${loadedCount} claim${loadedCount > 1 ? "s" : ""}${coverage.reservation ? " (Reservation)" : ""}`
                    )
                } else {
                    toast.error(`Could not load any claims for coverage #${coverageId}`)
                }
            } catch (error) {
                console.error("Error loading coverage:", error)
                toast.error(`Failed to fetch coverage #${coverageId}`)
            } finally {
                setIsLoadingCoverage(false)
            }
        },
        [chainId, config, contract.address, loadClaim, loadedCoverageIds]
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
            // Check if this was an approval transaction
            if (isApprovingPurchase) {
                toast.success("Approval successful! You can now purchase coverage.")
                setIsApprovingPurchase(false)
                resetPurchaseWrite()
                refetchAllowance()
                return
            }
            
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

                                // Load the coverage and its claims
                                await loadCoverage(coverageId)
                                break
                            }
                        } catch {
                            // Not the event we're looking for, continue
                        }
                    }
                } catch (error) {
                    console.error("Error parsing coverage creation logs:", error)
                }
                // Reset form and clear pending requests
                setPositionId("")
                setClaimAmount("")
                setClaimDuration("30")
                setClaimReward("")
                setPositionMaxAmount(null)
                setPendingRequests([])
            }
            loadCoverageClaimsAsync()
        }
        prevCreateSuccessRef.current = isSuccess
    }, [isSuccess, receipt, loadCoverage, isApprovingPurchase, resetPurchaseWrite, refetchAllowance])

    const handleAddCoverage = async () => {
        const id = Number(newCoverageId)
        if (isNaN(id) || id < 0) {
            toast.error("Please enter a valid coverage ID")
            return
        }
        await loadCoverage(id)
        setNewCoverageId("")
    }

    const handleRemoveClaim = (claimId: number, providerAddress: Address, coverageId: number) => {
        setLoadedClaims((prev) => {
            const newClaims = prev.filter(
                (c) => !(c.claimId === claimId && c.providerAddress === providerAddress)
            )
            // Check if any claims from this coverage remain
            const hasRemainingClaims = newClaims.some((c) => c.coverageId === coverageId)
            if (!hasRemainingClaims) {
                setLoadedCoverageIds((prevIds) => {
                    const next = new Set(prevIds)
                    next.delete(coverageId)
                    return next
                })
                setReservationCoverageIds((prevIds) => {
                    const next = new Set(prevIds)
                    next.delete(coverageId)
                    return next
                })
            }
            return newClaims
        })
    }


    const handleApprovePurchase = () => {
        if (!assetAddress || pendingRequests.length === 0) return

        setIsApprovingPurchase(true)
        writeContract(
            {
                address: assetAddress as Address,
                abi: ierc20Abi,
                functionName: "approve",
                args: [contract.address, totalPendingReward],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`Approval submitted: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    setIsApprovingPurchase(false)
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    const handleAddToList = () => {
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

        // Check amount doesn't exceed max
        if (positionMaxAmount !== null && amount > positionMaxAmount) {
            toast.error("Amount exceeds position max amount")
            return
        }

        const newRequest: PendingCoverageRequest = {
            id: `${selectedProviderAddress}-${positionId}-${Date.now()}`,
            providerAddress: selectedProviderAddress as Address,
            providerName: selectedProvider?.name || "Unknown Provider",
            positionId: BigInt(positionId),
            amount,
            duration,
            reward,
        }

        setPendingRequests((prev) => [...prev, newRequest])

        // Reset form fields (except provider and reservation toggle)
        setPositionId("")
        setClaimAmount("")
        setClaimDuration("30")
        setClaimReward("")
        setPositionMaxAmount(null)

        toast.success("Coverage request added to list")
    }

    const handleRemoveFromList = (requestId: string) => {
        setPendingRequests((prev) => prev.filter((r) => r.id !== requestId))
    }

    const handleClearList = () => {
        setPendingRequests([])
    }

    const handleSubmitCoverage = () => {
        if (pendingRequests.length === 0) {
            toast.error("No coverage requests to submit")
            return
        }

        // For non-reservation purchases, check balance and allowance
        if (!isReservation) {
            if (!purchaseHasSufficientBalance) {
                toast.error("Insufficient balance to pay the total reward")
                return
            }
            if (purchaseNeedsApproval) {
                toast.error("Please approve the token transfer first")
                return
            }
        }

        // Convert pending requests to contract format
        const requests = pendingRequests.map((req) => ({
            coverageProvider: req.providerAddress,
            positionId: req.positionId,
            amount: req.amount,
            reward: req.reward,
            duration: req.duration,
        }))

        // Use reserveCoverage if isReservation is true, otherwise use purchaseCoverage
        const successMessage = isReservation
            ? "Coverage reservation submitted"
            : "Coverage purchase submitted"

        writeContract(
            {
                address: contract.address,
                abi: iExampleCoverageAgentAbi,
                functionName: isReservation ? "reserveCoverage" : "purchaseCoverage",
                args: [requests],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    toast.success(`${successMessage}: ${hash.slice(0, 10)}...`)
                },
                onError: (error) => {
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
                },
            }
        )
    }

    // Group claims by coverage ID
    const claimsByCoverage = useMemo(() => {
        const grouped = new Map<number, LoadedClaimData[]>()
        for (const claim of loadedClaims) {
            const existing = grouped.get(claim.coverageId) || []
            grouped.set(claim.coverageId, [...existing, claim])
        }
        // Sort by coverage ID
        return Array.from(grouped.entries()).sort((a, b) => a[0] - b[0])
    }, [loadedClaims])

    const handleSlashSuccess = () => {
        if (slashCoverageId === null) return
        
        // Refresh claims for the slashed coverage
        const claimsToRefresh = loadedClaims.filter((c) => c.coverageId === slashCoverageId)
        claimsToRefresh.forEach((claimData) => {
            handleRemoveClaim(claimData.claimId, claimData.providerAddress, claimData.coverageId)
        })
        
        // Reload the coverage
        loadCoverage(slashCoverageId)
        setSlashCoverageId(null)
    }

    const handleConvertSuccess = () => {
        if (convertCoverageId === null) return
        
        // Remove coverage from reservation set
        setReservationCoverageIds((prev) => {
            const next = new Set(prev)
            next.delete(convertCoverageId)
            return next
        })
        
        // Refresh claim data for this coverage
        const claimsToRefresh = loadedClaims.filter((c) => c.coverageId === convertCoverageId)
        claimsToRefresh.forEach((claimData) => {
            handleRemoveClaim(claimData.claimId, claimData.providerAddress, claimData.coverageId)
        })
        
        // Reload the coverage
        loadCoverage(convertCoverageId)
        
        setConvertCoverageId(null)
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
                <WalletRequirement requiredChainId={contract.chainId}>
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
                                        {formatUnits(positionMaxAmount, tokenDecimals)}{" "}
                                        {tokenSymbol}
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
                                    BigInt(
                                        Math.floor(parseFloat(claimAmount) * 10 ** tokenDecimals)
                                    ) > positionMaxAmount && (
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

                        {/* Add to Coverage Button */}
                        <Button
                            onClick={handleAddToList}
                            disabled={!isValidClaimForm || isPending || isConfirming}
                            variant="secondary"
                            className="w-full"
                        >
                            <Plus className="mr-2 size-4" />
                            Add to Coverage
                        </Button>

                        {/* Pending Coverage Requests List */}
                        {pendingRequests.length > 0 && (
                            <div className="rounded-lg border p-4 space-y-3">
                                <div className="flex items-center justify-between">
                                    <h4 className="text-sm font-medium flex items-center gap-2">
                                        <Layers className="size-4" />
                                        Pending Coverage Requests
                                        <Badge variant="secondary">{pendingRequests.length}</Badge>
                                    </h4>
                                    <Button
                                        variant="ghost"
                                        size="sm"
                                        onClick={handleClearList}
                                        disabled={isPending || isConfirming}
                                    >
                                        <Trash2 className="size-4 mr-1" />
                                        Clear All
                                    </Button>
                                </div>

                                <ScrollArea className="max-h-[200px]">
                                    <div className="space-y-2">
                                        {pendingRequests.map((req, index) => (
                                            <div
                                                key={req.id}
                                                className="flex items-center justify-between rounded-md border bg-muted/30 p-2 text-sm"
                                            >
                                                <div className="flex-1 space-y-1">
                                                    <div className="flex items-center gap-2">
                                                        <Badge variant="outline" className="font-mono text-xs">
                                                            #{index + 1}
                                                        </Badge>
                                                        <span className="font-medium truncate max-w-[150px]">
                                                            {req.providerName}
                                                        </span>
                                                    </div>
                                                    <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-muted-foreground">
                                                        <span>Position: <span className="font-mono">{req.positionId.toString()}</span></span>
                                                        <span>Amount: <span className="font-mono">{formatUnits(req.amount, tokenDecimals)} {tokenSymbol}</span></span>
                                                        <span>Duration: <span className="font-mono">{Math.round(Number(req.duration) / 86400)} days</span></span>
                                                        <span>Reward: <span className="font-mono">{formatUnits(req.reward, tokenDecimals)} {tokenSymbol}</span></span>
                                                    </div>
                                                </div>
                                                <Button
                                                    variant="ghost"
                                                    size="icon"
                                                    className="size-8"
                                                    onClick={() => handleRemoveFromList(req.id)}
                                                    disabled={isPending || isConfirming}
                                                >
                                                    <X className="size-4" />
                                                </Button>
                                            </div>
                                        ))}
                                    </div>
                                </ScrollArea>

                                {/* Balance and Allowance Info - only show for non-reservation purchases */}
                                {!isReservation && totalPendingReward > 0n && (
                                    <div className="rounded-lg border bg-muted/50 p-3 space-y-2">
                                        <div className="grid gap-2 text-sm">
                                            <div className="flex items-center justify-between">
                                                <span className="text-muted-foreground">Your Balance</span>
                                                <span className={`font-mono ${!purchaseHasSufficientBalance ? "text-destructive" : ""}`}>
                                                    {userBalance !== undefined
                                                        ? `${formatUnits(userBalance as bigint, tokenDecimals)} ${tokenSymbol}`
                                                        : "Loading..."}
                                                </span>
                                            </div>
                                            <div className="flex items-center justify-between">
                                                <span className="text-muted-foreground">Current Allowance</span>
                                                <span className={`font-mono ${purchaseNeedsApproval ? "text-amber-600" : "text-green-600"}`}>
                                                    {currentAllowance !== undefined
                                                        ? `${formatUnits(currentAllowance as bigint, tokenDecimals)} ${tokenSymbol}`
                                                        : "Loading..."}
                                                </span>
                                            </div>
                                            <Separator />
                                            <div className="flex items-center justify-between font-medium">
                                                <span>Total Reward Required ({pendingRequests.length} positions)</span>
                                                <span className="font-mono">
                                                    {formatUnits(totalPendingReward, tokenDecimals)} {tokenSymbol}
                                                </span>
                                            </div>
                                        </div>

                                        {/* Warning messages */}
                                        {!purchaseHasSufficientBalance && (
                                            <div className="flex items-center gap-2 text-sm text-destructive mt-2">
                                                <AlertTriangle className="size-4" />
                                                <span>Insufficient balance to pay the total reward</span>
                                            </div>
                                        )}
                                        {purchaseHasSufficientBalance && purchaseNeedsApproval && (
                                            <div className="flex items-center gap-2 text-sm text-amber-600 mt-2">
                                                <AlertTriangle className="size-4" />
                                                <span>Token approval required before purchasing</span>
                                            </div>
                                        )}
                                        {purchaseHasSufficientBalance && !purchaseNeedsApproval && (
                                            <div className="flex items-center gap-2 text-sm text-green-600 mt-2">
                                                <CheckCircle2 className="size-4" />
                                                <span>Sufficient balance and allowance</span>
                                            </div>
                                        )}
                                    </div>
                                )}

                                <div className="flex gap-2">
                                    {/* Approve Button - show when approval is needed for non-reservation */}
                                    {!isReservation && purchaseNeedsApproval && totalPendingReward > 0n && (
                                        <Button
                                            variant="secondary"
                                            onClick={handleApprovePurchase}
                                            disabled={isPending || isConfirming || !purchaseHasSufficientBalance}
                                            className="flex-1"
                                        >
                                            {(isPending || isConfirming) && isApprovingPurchase ? (
                                                <Loader2 className="mr-2 size-4 animate-spin" />
                                            ) : (
                                                <CheckCircle2 className="mr-2 size-4" />
                                            )}
                                            {(isPending || isConfirming) && isApprovingPurchase
                                                ? isPending
                                                    ? "Confirm in wallet..."
                                                    : "Approving..."
                                                : `Approve ${formatUnits(totalPendingReward, tokenDecimals)} ${tokenSymbol}`}
                                        </Button>
                                    )}

                                    {/* Submit Coverage Button */}
                                    <Button
                                        onClick={handleSubmitCoverage}
                                        disabled={
                                            pendingRequests.length === 0 ||
                                            isPending ||
                                            isConfirming ||
                                            (!isReservation && (purchaseNeedsApproval || !purchaseHasSufficientBalance))
                                        }
                                        className="flex-1"
                                        variant={isReservation ? "outline" : "default"}
                                    >
                                        {(isPending || isConfirming) && !isApprovingPurchase ? (
                                            <Loader2 className="mr-2 size-4 animate-spin" />
                                        ) : (
                                            <ArrowRightLeft className="mr-2 size-4" />
                                        )}
                                        {(isPending || isConfirming) && !isApprovingPurchase
                                            ? isPending
                                                ? "Confirm in wallet..."
                                                : isReservation
                                                    ? "Reserving..."
                                                    : "Purchasing..."
                                            : isReservation
                                                ? `Reserve ${pendingRequests.length} Coverage${pendingRequests.length > 1 ? "s" : ""}`
                                                : `Purchase ${pendingRequests.length} Coverage${pendingRequests.length > 1 ? "s" : ""}`}
                                    </Button>
                                </div>
                            </div>
                        )}

                        {isSuccess && !isApprovingPurchase && (
                            <p className="flex items-center gap-2 text-sm text-green-600">
                                <CheckCircle2 className="size-4" />
                                {isReservation
                                    ? "Coverage reserved successfully!"
                                    : "Coverage purchased successfully!"}
                            </p>
                        )}
                    </div>

                    <Separator />

                    {/* View Coverage Section */}
                    <div className="space-y-4">
                        <div className="flex items-center justify-between">
                            <h4 className="text-sm font-medium">View Coverage</h4>
                            <div className="flex items-center gap-2">
                                <Badge variant="secondary">
                                    {loadedCoverageIds.size} coverage{loadedCoverageIds.size !== 1 ? "s" : ""}
                                </Badge>
                                <Badge variant="outline">{loadedClaims.length} claims</Badge>
                            </div>
                        </div>

                        <div className="flex gap-2">
                            <Input
                                placeholder="Coverage ID..."
                                value={newCoverageId}
                                onChange={(e) => setNewCoverageId(e.target.value)}
                                className="font-mono flex-1"
                                type="number"
                            />
                            <Button
                                variant="outline"
                                onClick={handleAddCoverage}
                                disabled={
                                    !newCoverageId ||
                                    isNaN(Number(newCoverageId)) ||
                                    isLoadingCoverage
                                }
                            >
                                {isLoadingCoverage ? (
                                    <Loader2 className="mr-2 size-4 animate-spin" />
                                ) : (
                                    <Plus className="mr-2 size-4" />
                                )}
                                {isLoadingCoverage ? "Loading..." : "Load Coverage"}
                            </Button>
                        </div>

                        {loadedClaims.length === 0 ? (
                            <div className="py-8 text-center text-sm text-muted-foreground">
                                Enter a coverage ID to view its claims
                            </div>
                        ) : (
                            <>
                                <ScrollArea className="h-fit">
                                    <div className="space-y-4 max-h-[500px]">
                                        {claimsByCoverage.map(([coverageId, claims]) => (
                                            <div
                                                key={coverageId}
                                                className="rounded-lg border bg-card"
                                            >
                                                {/* Coverage Header */}
                                                <div className="flex items-center justify-between border-b bg-muted/50 px-4 py-3 rounded-t-lg">
                                                    <div className="flex items-center gap-2">
                                                        <Layers className="size-4 text-muted-foreground" />
                                                        <span className="font-medium">
                                                            Coverage #{coverageId}
                                                        </span>
                                                        <Badge variant="outline">
                                                            {claims.length} claim
                                                            {claims.length !== 1 ? "s" : ""}
                                                        </Badge>
                                                        {reservationCoverageIds.has(coverageId) && (
                                                            <Badge variant="secondary">Reserved</Badge>
                                                        )}
                                                    </div>
                                                    <div className="flex items-center gap-1">
                                                        {reservationCoverageIds.has(coverageId) && (
                                                            <Button
                                                                variant="ghost"
                                                                size="sm"
                                                                onClick={() => {
                                                                    setConvertCoverageId(coverageId)
                                                                    setConvertDialogOpen(true)
                                                                }}
                                                                title="Convert reserved coverage"
                                                            >
                                                                <ArrowRightLeft className="size-4 mr-1" />
                                                                Convert
                                                            </Button>
                                                        )}
                                                        {!reservationCoverageIds.has(coverageId) && (
                                                            <Button
                                                                variant="ghost"
                                                                size="sm"
                                                                onClick={() => {
                                                                    setSlashCoverageId(coverageId)
                                                                    setSlashDialogOpen(true)
                                                                }}
                                                                title="Slash coverage"
                                                                className="text-destructive hover:text-destructive"
                                                            >
                                                                <Zap className="size-4 mr-1" />
                                                                Slash
                                                            </Button>
                                                        )}
                                                        <Button
                                                            variant="ghost"
                                                            size="sm"
                                                            onClick={() => {
                                                                // Remove all claims from this coverage
                                                                claims.forEach((c) =>
                                                                    handleRemoveClaim(
                                                                        c.claimId,
                                                                        c.providerAddress,
                                                                        c.coverageId
                                                                    )
                                                                )
                                                            }}
                                                            title="Remove coverage"
                                                        >
                                                            <Trash2 className="size-4" />
                                                        </Button>
                                                    </div>
                                                </div>

                                                {/* Claims List */}
                                                <div className="p-3 space-y-3">
                                                    {claims.map((claimData) => (
                                                        <ClaimItem
                                                            key={`${claimData.providerAddress}-${claimData.claimId}`}
                                                            claimData={claimData}
                                                            totalSlashAmount={claimData.totalSlashAmount}
                                                            tokenDecimals={tokenDecimals}
                                                            tokenSymbol={tokenSymbol}
                                                        />
                                                    ))}
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </ScrollArea>

                            </>
                        )}
                    </div>

                    {/* Slash Coverage Dialog */}
                    <SlashCoverageDialog
                        open={slashDialogOpen}
                        onOpenChange={setSlashDialogOpen}
                        coverageId={slashCoverageId}
                        claims={loadedClaims.filter((c) => c.coverageId === slashCoverageId)}
                        contractAddress={contract.address}
                        chainId={chainId}
                        tokenDecimals={tokenDecimals}
                        tokenSymbol={tokenSymbol}
                        onSuccess={handleSlashSuccess}
                    />

                    {/* Convert Coverage Dialog */}
                    <ConvertCoverageDialog
                        open={convertDialogOpen}
                        onOpenChange={setConvertDialogOpen}
                        coverageId={convertCoverageId}
                        claims={loadedClaims.filter((c) => c.coverageId === convertCoverageId)}
                        contractAddress={contract.address}
                        assetAddress={assetAddress as Address | undefined}
                        chainId={chainId}
                        tokenDecimals={tokenDecimals}
                        tokenSymbol={tokenSymbol}
                        onSuccess={handleConvertSuccess}
                    />
                </WalletRequirement>
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
    const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } = useWaitForTransactionReceipt({ hash })

    // Track previous success state to detect new success
    const prevSuccessRef = useRef(false)
    const hasShownReceiptError = useRef<string>("")

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

    // Handle transaction receipt errors (transaction was mined but reverted)
    useEffect(() => {
        if (isReceiptError && receiptError && hash && hasShownReceiptError.current !== hash) {
            hasShownReceiptError.current = hash
            const decodedError = decodeContractError(receiptError)
            toast.error(`Transaction failed: ${decodedError}`, {
                duration: 10000,
            })
        }
    }, [isReceiptError, receiptError, hash])

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
                    const decodedError = decodeContractError(error)
                    toast.error(decodedError, {
                        duration: 8000,
                    })
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
                    <WalletRequirement requiredChainId={contract.chainId}>
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
                    </WalletRequirement>
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
