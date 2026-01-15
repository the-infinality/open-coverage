import { useState, useEffect } from "react"
import { useParams } from "react-router-dom"
import { useChainId, useSwitchChain, useAccount } from "wagmi"
import { toast } from "sonner"
import type { SavedContract } from "@/types/contracts"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
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
  onContractChange?: (contract: SavedContract | null) => void
}

export function ContractSelector({
  title = "Select Contract",
  description = "Choose a contract",
  onContractChange,
}: ContractSelectorProps) {
  const { contractId } = useParams<{ contractId?: string }>()
  const { contracts, getContractById } = useContracts()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()
  const { isConnected } = useAccount()
  const [selectedContractId, setSelectedContractId] = useState<string | null>(
    contractId || null
  )

  const selectedContract = selectedContractId
    ? getContractById(selectedContractId)
    : null

  // Auto-switch chain when contract is selected
  useEffect(() => {
    if (selectedContract && isConnected && selectedContract.chainId !== chainId) {
      switchChain({ chainId: selectedContract.chainId as 1 | 11155111 | 31337 })
      toast.info(`Switching to ${getChainInfo(selectedContract.chainId)?.name || 'network'}...`)
    }
  }, [selectedContract, chainId, isConnected, switchChain])

  // Notify parent component when contract changes
  useEffect(() => {
    onContractChange?.(selectedContract || null)
  }, [selectedContract, onContractChange])

  // Show all contracts (not filtered by chain)
  const allContracts = contracts

  const handleValueChange = (value: string) => {
    setSelectedContractId(value)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Select
          value={selectedContractId || ""}
          onValueChange={handleValueChange}
        >
          <SelectTrigger>
            <SelectValue placeholder="Select a contract" />
          </SelectTrigger>
          <SelectContent>
            {allContracts.map((contract) => (
              <SelectItem key={contract.id} value={contract.id}>
                <div className="flex items-center gap-2">
                  <span>{contract.name}</span>
                  <span className="text-muted-foreground">({truncateAddress(contract.address)})</span>
                  <ChainBadge chainId={contract.chainId} size="sm" showIcon={false} />
                </div>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {selectedContract && (
          <div className="rounded-lg border p-4 bg-muted/50">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-medium">{selectedContract.name}</span>
              <span className="text-muted-foreground">-</span>
              <CopyableAddress address={selectedContract.address} truncateChars={8} variant="inline" size="sm" />
              <span className="text-muted-foreground">-</span>
              <span className="text-sm text-muted-foreground">{selectedContract.type}</span>
              <span className="text-muted-foreground">-</span>
              <ChainBadge chainId={selectedContract.chainId} size="sm" />
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

