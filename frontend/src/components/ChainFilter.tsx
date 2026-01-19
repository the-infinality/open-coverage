import { useMemo } from "react"
import { Filter, X } from "lucide-react"
import { getChainInfo } from "@/lib/wagmi"
import { Checkbox } from "@/components/ui/checkbox"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ChainBadge } from "@/components/ui/chain-badge"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"

interface ChainFilterProps {
  selectedChainIds: Set<number>
  onSelectionChange: (chainIds: Set<number>) => void
  availableChainIds: number[]
}

export function ChainFilter({
  selectedChainIds,
  onSelectionChange,
  availableChainIds,
}: ChainFilterProps) {
  // Get chain info for available chains
  const availableChains = useMemo(() => {
    return availableChainIds
      .map((id) => getChainInfo(id))
      .filter((chain): chain is NonNullable<typeof chain> => chain !== undefined)
      .sort((a, b) => {
        // Sort mainnet first, then testnets, then others
        if (a.id === 1) return -1
        if (b.id === 1) return 1
        if (a.isTestnet && !b.isTestnet) return -1
        if (!a.isTestnet && b.isTestnet) return 1
        return a.name.localeCompare(b.name)
      })
  }, [availableChainIds])

  const toggleChain = (chainId: number) => {
    const next = new Set(selectedChainIds)
    if (next.has(chainId)) {
      next.delete(chainId)
    } else {
      next.add(chainId)
    }
    onSelectionChange(next)
  }

  const handleSelectAll = () => {
    onSelectionChange(new Set(availableChainIds))
  }

  const handleClear = () => {
    onSelectionChange(new Set())
  }

  const selectedCount = selectedChainIds.size
  const allSelected = selectedChainIds.size === availableChainIds.length
  const hasFilter = selectedCount > 0

  return (
    <Collapsible className="w-fit">
      <div className="flex items-center gap-2 flex-wrap w-fit">
        <CollapsibleTrigger asChild>
          <Button variant="outline" size="sm" className="gap-2">
            <Filter className="size-4" />
            <span>Chain</span>
            {hasFilter && (
              <Badge variant="secondary" className="ml-1">
                {allSelected ? "All" : selectedCount}
              </Badge>
            )}
          </Button>
        </CollapsibleTrigger>
        {hasFilter && (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleClear}
            className="gap-1 h-8"
          >
            <X className="size-3" />
            Clear Filter
          </Button>
        )}
      </div>
      <CollapsibleContent className="mt-3">
        <div className="rounded-lg border bg-card p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-sm">Select Chains</h4>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleSelectAll}
              className="h-7 text-xs"
            >
              {allSelected ? "Deselect All" : "Select All"}
            </Button>
          </div>
          <div className="flex flex-wrap gap-2">
            {availableChains.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No chains available
              </p>
            ) : (
              availableChains.map((chain) => {
                const isSelected = selectedChainIds.has(chain.id)
                return (
                  <div
                    key={chain.id}
                    className="flex items-center gap-2 rounded-lg border p-2 hover:bg-accent/50 transition-colors cursor-pointer"
                    onClick={() => toggleChain(chain.id)}
                  >
                    <Checkbox
                      checked={isSelected}
                      onChange={() => toggleChain(chain.id)}
                    />
                    <ChainBadge chainId={chain.id} size="sm" />
                  </div>
                )
              })
            )}
          </div>
          {selectedCount > 0 && (
            <div className="pt-2 border-t text-xs text-muted-foreground">
              {selectedCount} of {availableChainIds.length} chain
              {availableChainIds.length !== 1 ? "s" : ""} selected
            </div>
          )}
        </div>
      </CollapsibleContent>
    </Collapsible>
  )
}

