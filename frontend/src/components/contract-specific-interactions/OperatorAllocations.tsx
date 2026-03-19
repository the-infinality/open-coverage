import { useState, useEffect, useMemo } from "react"
import { type Address, BaseError } from "viem"
import { useReadContract, useWriteContract, useConfig } from "wagmi"
import { readContract } from "wagmi/actions"
import { Loader2, Layers, ExternalLink, Plus } from "lucide-react"
import { Link } from "react-router-dom"
import { toast } from "sonner"
import type { CoverageContract } from "@/types/contracts"
import { useContracts } from "@/hooks/use-contracts"
import { generateContractName } from "@/lib/utils"
import { getSupportedChainsInfo } from "@/lib/wagmi"
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { iAllocationManagerAbi, iStrategyAbi, ierc20Abi } from "@/generated/eigen-abis"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Badge } from "@/components/ui/badge"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { supportedChains } from "@/lib/wagmi"

type SupportedChainId = (typeof supportedChains)[number]["id"]

function decodeContractError(error: unknown): string {
    if (error instanceof BaseError) {
        const revertMatch = error.message?.match(/reverted with reason string '([^']+)'/)
        if (revertMatch) return revertMatch[1]
        if (error.shortMessage) return error.shortMessage
    }
    const message = error instanceof Error ? error.message : String(error)
    return message.length > 200 ? message.slice(0, 200) + "..." : message
}

type AllSetsAllocRow = {
    strategy: Address
    maxMagnitude: bigint
    currentMagnitude: bigint
    pendingDiff: bigint
    effectBlock: number
    initialPercent: number
    percent: number
    tokenSymbol: string
}

type AllSetsAllocGroup = {
    operatorSet: { avs: Address; id: number }
    rows: AllSetsAllocRow[]
}

export interface OperatorAllocationsProps {
    chainId: SupportedChainId | undefined
    connectedAddress: Address | undefined
    allocationManager: Address | undefined
    isOperator: boolean | undefined
    /** Saved service managers on this chain (for AVS labels) */
    serviceManagers: CoverageContract[]
    isPendingAllocate: boolean
    /** Parent tx receipt loading (any operator tx) */
    isConfirmingTx: boolean
    /** Called when this component submits a tx hash (parent watches receipt) */
    onTxSubmitted: (hash: `0x${string}`) => void
    /** Parent disables per-set allocate while cross-set modify is pending */
    onCrossSetAllocatePending?: (pending: boolean) => void
    /** Increment after any successful allocation-related tx to refresh this panel */
    allocationRefreshKey: number
    /** Coverage provider (AVS) address for this page — used for "THIS AVS" badge */
    currentServiceManagerAddress?: Address
}

export function OperatorAllocations({
    chainId,
    connectedAddress,
    allocationManager,
    isOperator,
    serviceManagers,
    isPendingAllocate,
    isConfirmingTx,
    onTxSubmitted,
    onCrossSetAllocatePending,
    allocationRefreshKey,
    currentServiceManagerAddress,
}: OperatorAllocationsProps) {
    const config = useConfig()
    const { addContract, contracts } = useContracts()

    const [addAvsDialogOpen, setAddAvsDialogOpen] = useState(false)
    const [addAvsPayload, setAddAvsPayload] = useState<{
        address: Address
        chainId: number
    } | null>(null)
    const [addAvsName, setAddAvsName] = useState("")

    const { data: allocatedSetsAll, refetch: refetchAllocatedSets } = useReadContract({
        address: allocationManager,
        abi: iAllocationManagerAbi,
        functionName: "getAllocatedSets",
        args: connectedAddress ? [connectedAddress] : undefined,
        chainId,
        query: {
            enabled: !!allocationManager && !!connectedAddress && !!chainId && !!isOperator,
        },
    })

    const [allSetsAllocations, setAllSetsAllocations] = useState<AllSetsAllocGroup[]>([])
    const [loadingAllSetsAllocations, setLoadingAllSetsAllocations] = useState(false)
    const [loadMatrixNonce, setLoadMatrixNonce] = useState(0)

    const { mutate: writeModifyAllOperatorSets, isPending: isPendingModifyAllOperatorSets } =
        useWriteContract()

    useEffect(() => {
        onCrossSetAllocatePending?.(isPendingModifyAllOperatorSets)
    }, [isPendingModifyAllOperatorSets, onCrossSetAllocatePending])

    useEffect(() => {
        if (allocationRefreshKey > 0) {
            void refetchAllocatedSets().finally(() => setLoadMatrixNonce((n) => n + 1))
        }
    }, [allocationRefreshKey, refetchAllocatedSets])

    useEffect(() => {
        if (!isOperator || !chainId || !connectedAddress || !allocationManager) {
            setAllSetsAllocations([])
            setLoadingAllSetsAllocations(false)
            return
        }
        if (allocatedSetsAll === undefined) {
            setLoadingAllSetsAllocations(true)
            return
        }
        const sets = allocatedSetsAll as Array<{ avs: Address; id: number }>
        if (sets.length === 0) {
            setAllSetsAllocations([])
            setLoadingAllSetsAllocations(false)
            return
        }
        let cancelled = false
        setLoadingAllSetsAllocations(true)
        ;(async () => {
            const groups: AllSetsAllocGroup[] = []
            for (const operatorSet of sets) {
                try {
                    const strategies = (await readContract(config, {
                        address: allocationManager,
                        abi: iAllocationManagerAbi,
                        functionName: "getAllocatedStrategies",
                        args: [connectedAddress, operatorSet],
                        chainId,
                    })) as Address[]
                    if (strategies.length === 0) continue
                    const maxMagnitudes = (await readContract(config, {
                        address: allocationManager,
                        abi: iAllocationManagerAbi,
                        functionName: "getMaxMagnitudes",
                        args: [connectedAddress, strategies],
                        chainId,
                    })) as bigint[]
                    const rows: AllSetsAllocRow[] = []
                    for (let i = 0; i < strategies.length; i++) {
                        const strategy = strategies[i]
                        const allocation = await readContract(config, {
                            address: allocationManager,
                            abi: iAllocationManagerAbi,
                            functionName: "getAllocation",
                            args: [connectedAddress, operatorSet, strategy],
                            chainId,
                        })
                        const max = maxMagnitudes[i] ?? 0n
                        const current = allocation.currentMagnitude
                        const pct =
                            max === 0n
                                ? 0
                                : Math.min(100, Math.round(Number((current * 100n) / max)))
                        let tokenSymbol = "Strategy"
                        try {
                            const underlying = await readContract(config, {
                                address: strategy,
                                abi: iStrategyAbi,
                                functionName: "underlyingToken",
                                chainId,
                            })
                            if (underlying && typeof underlying === "string") {
                                const sym = await readContract(config, {
                                    address: underlying as Address,
                                    abi: ierc20Abi,
                                    functionName: "symbol",
                                    chainId,
                                })
                                if (typeof sym === "string") tokenSymbol = sym
                            }
                        } catch {
                            /* optional */
                        }
                        rows.push({
                            strategy,
                            maxMagnitude: max,
                            currentMagnitude: current,
                            pendingDiff: allocation.pendingDiff,
                            effectBlock: allocation.effectBlock,
                            initialPercent: pct,
                            percent: pct,
                            tokenSymbol,
                        })
                    }
                    groups.push({ operatorSet, rows })
                } catch {
                    /* skip broken set */
                }
            }
            if (!cancelled) setAllSetsAllocations(groups)
        })()
            .catch(() => {
                if (!cancelled) setAllSetsAllocations([])
            })
            .finally(() => {
                if (!cancelled) setLoadingAllSetsAllocations(false)
            })
        return () => {
            cancelled = true
        }
    }, [
        allocatedSetsAll,
        chainId,
        connectedAddress,
        allocationManager,
        config,
        isOperator,
        loadMatrixNonce,
    ])

    const updateAllSetsRowPercent = (groupIndex: number, rowIndex: number, percent: number) => {
        setAllSetsAllocations((prev) =>
            prev.map((g, gi) =>
                gi !== groupIndex
                    ? g
                    : {
                          ...g,
                          rows: g.rows.map((r, ri) => (ri === rowIndex ? { ...r, percent } : r)),
                      }
            )
        )
    }

    const hasAllOperatorSetsAllocChanges = useMemo(
        () => allSetsAllocations.some((g) => g.rows.some((r) => r.percent !== r.initialPercent)),
        [allSetsAllocations]
    )

    const handleApplyAllOperatorSetsAllocations = async () => {
        if (!allocationManager || !connectedAddress) {
            toast.error("Not connected or addresses not loaded")
            return
        }
        const params: Array<{
            operatorSet: { avs: Address; id: number }
            strategies: Address[]
            newMagnitudes: bigint[]
        }> = []
        for (const group of allSetsAllocations) {
            const dirty = group.rows.some((r) => r.percent !== r.initialPercent)
            if (!dirty) continue
            const strategies = group.rows.map((r) => r.strategy)
            const maxMagnitudes = (await readContract(config, {
                address: allocationManager,
                abi: iAllocationManagerAbi,
                functionName: "getMaxMagnitudes",
                args: [connectedAddress, strategies],
                chainId,
            })) as bigint[]
            const newMagnitudes = group.rows.map((r, i) => {
                const max = maxMagnitudes[i] ?? 0n
                return max === 0n ? 0n : (max * BigInt(r.percent)) / 100n
            })
            const hasPositive = newMagnitudes.some((m) => m > 0n)
            const hasZeroMax = group.rows.some(
                (_, i) => (maxMagnitudes[i] ?? 0n) === 0n && newMagnitudes[i] > 0n
            )
            if (hasPositive && hasZeroMax) {
                toast.error(
                    `Operator set #${group.operatorSet.id}: no allocatable stake for one or more strategies`
                )
                return
            }
            params.push({
                operatorSet: group.operatorSet,
                strategies,
                newMagnitudes,
            })
        }
        if (params.length === 0) {
            toast.info("No allocation changes to apply")
            return
        }
        writeModifyAllOperatorSets(
            {
                address: allocationManager,
                abi: iAllocationManagerAbi,
                functionName: "modifyAllocations",
                args: [connectedAddress, params],
                chainId,
            },
            {
                onSuccess: (hash) => {
                    onTxSubmitted(hash)
                    toast.success(
                        `Updated allocations across ${params.length} operator set(s): ${hash.slice(0, 10)}...`
                    )
                },
                onError: (error) => {
                    toast.error(decodeContractError(error), { duration: 8000 })
                },
            }
        )
    }

    return (
        <>
            <div className="space-y-4 rounded-lg border border-dashed p-4 bg-background/50">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div className="space-y-1">
                        <h4 className="text-sm font-medium flex items-center gap-2">
                            <Layers className="size-4 shrink-0" />
                            All operator set allocations
                        </h4>
                        <p className="text-xs text-muted-foreground max-w-prose">
                            Loads every strategy you already allocate across <strong>all</strong>{" "}
                            operator sets (any coverage provider). Adjust percentages and apply in
                            one transaction. Adding strategies is not available here — use{" "}
                            <strong>Coverage Agent Setup</strong> section above to select a coverage
                            agent an allocate on this provider.
                        </p>
                    </div>
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        className="shrink-0"
                        disabled={
                            !isOperator ||
                            loadingAllSetsAllocations ||
                            isPendingModifyAllOperatorSets ||
                            isConfirmingTx
                        }
                        onClick={() => void refetchAllocatedSets()}
                    >
                        {loadingAllSetsAllocations ? (
                            <Loader2 className="size-3.5 animate-spin" />
                        ) : (
                            "Refresh"
                        )}
                    </Button>
                </div>

                {!isOperator ? (
                    <p className="text-xs text-muted-foreground">
                        Register as an operator to manage cross-set allocations.
                    </p>
                ) : loadingAllSetsAllocations ? (
                    <div className="flex items-center gap-2 text-sm text-muted-foreground py-2">
                        <Loader2 className="size-4 animate-spin" />
                        Loading strategy allocations…
                    </div>
                ) : allSetsAllocations.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                        No strategy allocations on any operator set yet. Use{" "}
                        <span className="font-medium">Allocate to Strategies</span> after selecting
                        a coverage agent.
                    </p>
                ) : (
                    <>
                        {allSetsAllocations.map((group, gi) => {
                            const avsInStorage = serviceManagers.find(
                                (c) =>
                                    c.address?.toLowerCase() ===
                                    group.operatorSet.avs?.toLowerCase()
                            )
                            const isCurrentAvs =
                                !!currentServiceManagerAddress &&
                                group.operatorSet.avs?.toLowerCase() ===
                                    currentServiceManagerAddress.toLowerCase()
                            return (
                                <div
                                    key={`${group.operatorSet.avs}-${group.operatorSet.id}`}
                                    className="rounded-lg border bg-muted/20 p-3 space-y-3 text-xs"
                                >
                                    <div className="flex items-center justify-between gap-2 flex-wrap">
                                        <span className="text-muted-foreground">AVS:</span>
                                        <span className="flex items-center gap-2 flex-wrap justify-end">
                                            {isCurrentAvs ? (
                                                <Badge variant="default" className="text-xs">
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
                                                            address: group.operatorSet.avs,
                                                            chainId: chainId ?? 0,
                                                        })
                                                        setAddAvsName(
                                                            generateContractName(
                                                                "CoverageProvider",
                                                                contracts
                                                            )
                                                        )
                                                        setAddAvsDialogOpen(true)
                                                    }}
                                                    className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium border border-input bg-background hover:bg-accent hover:text-accent-foreground"
                                                >
                                                    <Plus className="size-3" />
                                                    Add
                                                </button>
                                            )}
                                            <CopyableAddress address={group.operatorSet.avs} />
                                            {avsInStorage && (
                                                <Badge
                                                    variant="outline"
                                                    className="text-xs shrink-0"
                                                >
                                                    {avsInStorage.name}
                                                </Badge>
                                            )}
                                        </span>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-muted-foreground">
                                            Operator Set ID:
                                        </span>
                                        <span className="font-mono font-medium">
                                            {group.operatorSet.id}
                                        </span>
                                    </div>
                                    {group.rows.map((row, ri) => (
                                        <div
                                            key={`${row.strategy}-${ri}`}
                                            className="rounded-md border bg-card p-3 space-y-2"
                                        >
                                            <div className="flex justify-between items-center gap-2 flex-wrap">
                                                <span className="text-sm font-medium">
                                                    {row.tokenSymbol}
                                                </span>
                                                <div className="flex items-center gap-2">
                                                    {row.pendingDiff !== 0n && (
                                                        <Badge
                                                            variant="secondary"
                                                            className="text-[10px]"
                                                        >
                                                            Pending on-chain
                                                        </Badge>
                                                    )}
                                                    <span className="text-sm font-medium tabular-nums">
                                                        {row.percent}%
                                                    </span>
                                                </div>
                                            </div>
                                            <CopyableAddress
                                                address={row.strategy}
                                                truncateChars={8}
                                                variant="inline"
                                                size="sm"
                                                className="text-xs text-muted-foreground"
                                            />
                                            <Slider
                                                value={[row.percent]}
                                                onValueChange={(v) =>
                                                    updateAllSetsRowPercent(gi, ri, v[0] ?? 0)
                                                }
                                                min={0}
                                                max={100}
                                                step={1}
                                                disabled={
                                                    isPendingModifyAllOperatorSets ||
                                                    isPendingAllocate ||
                                                    isConfirmingTx ||
                                                    loadingAllSetsAllocations
                                                }
                                            />
                                        </div>
                                    ))}
                                </div>
                            )
                        })}
                        <Button
                            className="w-full"
                            disabled={
                                !hasAllOperatorSetsAllocChanges ||
                                isPendingModifyAllOperatorSets ||
                                isPendingAllocate ||
                                isConfirmingTx
                            }
                            onClick={() => void handleApplyAllOperatorSetsAllocations()}
                        >
                            {isPendingModifyAllOperatorSets || isConfirmingTx ? (
                                <Loader2 className="mr-2 size-4 animate-spin" />
                            ) : (
                                <Layers className="mr-2 size-4" />
                            )}
                            {isPendingModifyAllOperatorSets
                                ? "Confirm in wallet…"
                                : isConfirmingTx
                                  ? "Confirming…"
                                  : "Apply changes (all modified sets)"}
                        </Button>
                    </>
                )}
            </div>

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
                                <Label htmlFor="op-alloc-add-avs-name">Name</Label>
                                <Input
                                    id="op-alloc-add-avs-name"
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
