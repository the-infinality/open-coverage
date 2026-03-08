import { useEffect } from "react"
import { useChainId, useSwitchChain, useAccount } from "wagmi"
import { toast } from "sonner"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select"
import { useContracts } from "@/hooks/use-contracts"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { ChainBadge } from "@/components/ui/chain-badge"
import { truncateAddress } from "@/lib/utils"
import { getChainInfo } from "@/lib/wagmi"

interface ContractSelectorProps {
    title?: string
    description?: string
    contractId?: string
    onContractChange?: (contractId: string | null) => void
}

export function ContractSelector({
    title = "Select Contract",
    description = "Choose a contract",
    contractId,
    onContractChange,
}: ContractSelectorProps) {
    const { contracts, getContractById } = useContracts()
    const chainId = useChainId()
    const { switchChain } = useSwitchChain()
    const { isConnected } = useAccount()

    const selectedContract = contractId ? getContractById(contractId) : null

    // Auto-switch chain when contract is selected
    useEffect(() => {
        if (selectedContract && isConnected && selectedContract.chainId !== chainId) {
            switchChain({ chainId: selectedContract.chainId as 1 | 11155111 | 31337 })
            toast.info(
                `Switching to ${getChainInfo(selectedContract.chainId)?.name || "network"}...`
            )
        }
    }, [selectedContract, chainId, isConnected, switchChain])

    // Show all contracts (not filtered by chain)
    const allContracts = contracts

    const handleValueChange = (value: string) => {
        onContractChange?.(value || null)
    }

    return (
        <Card>
            <CardHeader>
                <CardTitle>{title}</CardTitle>
                <CardDescription>{description}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
                <Select value={contractId || ""} onValueChange={handleValueChange}>
                    <SelectTrigger>
                        <SelectValue placeholder="Select a contract" />
                    </SelectTrigger>
                    <SelectContent>
                        {allContracts.map((contract) => (
                            <SelectItem key={contract.id} value={contract.id}>
                                <div className="flex items-center gap-2">
                                    <div>{contract.name}</div>
                                    <div className="text-muted-foreground">
                                        ({truncateAddress(contract.address)})
                                    </div>
                                    <ChainBadge
                                        chainId={contract.chainId}
                                        size="sm"
                                        showIcon={false}
                                    />
                                </div>
                            </SelectItem>
                        ))}
                    </SelectContent>
                </Select>

                {selectedContract && (
                    <div className="rounded-lg border p-4 bg-muted/50 space-y-2 text-sm">
                        <div className="flex flex-col gap-0.5">
                            <span className="text-muted-foreground text-xs">Name</span>
                            <span className="font-medium">{selectedContract.name}</span>
                        </div>
                        <div className="flex flex-col gap-0.5">
                            <span className="text-muted-foreground text-xs">Address</span>
                            <CopyableAddress
                                address={selectedContract.address}
                                truncateChars={10}
                                variant="inline"
                                size="sm"
                            />
                        </div>
                        <div className="flex flex-col gap-0.5">
                            <span className="text-muted-foreground text-xs">Type</span>
                            <span>{selectedContract.type}</span>
                        </div>
                        <div className="flex flex-col gap-0.5">
                            <span className="text-muted-foreground text-xs">Chain</span>
                            <ChainBadge chainId={selectedContract.chainId} size="sm" />
                        </div>
                    </div>
                )}
            </CardContent>
        </Card>
    )
}
