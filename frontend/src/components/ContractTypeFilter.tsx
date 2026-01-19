import { useMemo } from "react"
import { Filter, X } from "lucide-react"
import { Checkbox } from "@/components/ui/checkbox"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import type { ContractType } from "@/types/contracts"
import { getContractTypeLabel } from "@/lib/contract-utils"

interface ContractTypeFilterProps {
    selectedTypes: Set<ContractType>
    onSelectionChange: (types: Set<ContractType>) => void
    availableTypes: ContractType[]
}

export function ContractTypeFilter({
    selectedTypes,
    onSelectionChange,
    availableTypes,
}: ContractTypeFilterProps) {
    // Sort types alphabetically by label
    const sortedTypes = useMemo(() => {
        return [...availableTypes].sort((a, b) =>
            getContractTypeLabel(a).localeCompare(getContractTypeLabel(b))
        )
    }, [availableTypes])

    const toggleType = (type: ContractType) => {
        const next = new Set(selectedTypes)
        if (next.has(type)) {
            next.delete(type)
        } else {
            next.add(type)
        }
        onSelectionChange(next)
    }

    const handleSelectAll = () => {
        onSelectionChange(new Set(availableTypes))
    }

    const handleClear = () => {
        onSelectionChange(new Set())
    }

    const selectedCount = selectedTypes.size
    const allSelected = selectedTypes.size === availableTypes.length
    const hasFilter = selectedCount > 0

    return (
        <Collapsible className="w-fit">
            <div className="flex items-center gap-2 flex-wrap w-fit">
                <CollapsibleTrigger asChild>
                    <Button variant="outline" size="sm" className="gap-2">
                        <Filter className="size-4" />
                        <span>Type</span>
                        {hasFilter && (
                            <Badge variant="secondary" className="ml-1">
                                {allSelected ? "All" : selectedCount}
                            </Badge>
                        )}
                    </Button>
                </CollapsibleTrigger>
                {hasFilter && (
                    <Button variant="ghost" size="sm" onClick={handleClear} className="gap-1 h-8">
                        <X className="size-3" />
                        Clear Filter
                    </Button>
                )}
            </div>
            <CollapsibleContent className="mt-3">
                <div className="rounded-lg border bg-card p-4 space-y-3">
                    <div className="flex items-center justify-between">
                        <h4 className="font-medium text-sm">Select Contract Types</h4>
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
                        {sortedTypes.length === 0 ? (
                            <p className="text-sm text-muted-foreground">
                                No contract types available
                            </p>
                        ) : (
                            sortedTypes.map((type) => {
                                const isSelected = selectedTypes.has(type)
                                return (
                                    <div
                                        key={type}
                                        className="flex items-center gap-2 rounded-lg border p-2 hover:bg-accent/50 transition-colors cursor-pointer"
                                        onClick={() => toggleType(type)}
                                    >
                                        <Checkbox
                                            checked={isSelected}
                                            onChange={() => toggleType(type)}
                                        />
                                        <Badge variant="outline">
                                            {getContractTypeLabel(type)}
                                        </Badge>
                                    </div>
                                )
                            })
                        )}
                    </div>
                    {selectedCount > 0 && (
                        <div className="pt-2 border-t text-xs text-muted-foreground">
                            {selectedCount} of {availableTypes.length} type
                            {availableTypes.length !== 1 ? "s" : ""} selected
                        </div>
                    )}
                </div>
            </CollapsibleContent>
        </Collapsible>
    )
}
