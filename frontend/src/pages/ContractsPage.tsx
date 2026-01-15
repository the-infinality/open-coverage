import { useRef, useState, useEffect, useMemo } from "react"
import { Link } from "react-router-dom"
import { FileCode, Download, Upload } from "lucide-react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Checkbox } from "@/components/ui/checkbox"
import { ScrollArea } from "@/components/ui/scroll-area"
import { useContracts } from "@/hooks/use-contracts"
import { ContractCard } from "@/components/ContractCard"
import { getContractTypeLabel } from "@/lib/contract-utils"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { ChainBadge } from "@/components/ui/chain-badge"
import { Badge } from "@/components/ui/badge"
import { ChainFilter } from "@/components/ChainFilter"

export function ContractsPage() {
  const { contracts, exportContracts, importContracts } = useContracts()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [isImporting, setIsImporting] = useState(false)
  const [isExportDialogOpen, setIsExportDialogOpen] = useState(false)
  const [selectedContractIds, setSelectedContractIds] = useState<Set<string>>(
    new Set()
  )
  const [selectedChainIds, setSelectedChainIds] = useState<Set<number>>(
    new Set()
  )

  // Get unique chain IDs from contracts
  const availableChainIds = useMemo(() => {
    return Array.from(new Set(contracts.map((c) => c.chainId)))
  }, [contracts])

  // Initialize all chains as selected when component mounts or contracts change
  useEffect(() => {
    if (availableChainIds.length === 0) return

    // If no chains are selected, select all available
    if (selectedChainIds.size === 0) {
      setSelectedChainIds(new Set(availableChainIds))
      return
    }

    // Update selection to only include available chains
    const validChainIds = availableChainIds.filter((id) =>
      selectedChainIds.has(id)
    )
    if (validChainIds.length === 0) {
      // If no valid chains, select all available
      setSelectedChainIds(new Set(availableChainIds))
    } else if (validChainIds.length !== selectedChainIds.size) {
      // If some chains are no longer available, update selection
      setSelectedChainIds(new Set(validChainIds))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [availableChainIds])

  // Filter contracts by selected chains
  const filteredContracts = useMemo(() => {
    if (selectedChainIds.size === 0) return contracts
    return contracts.filter((c) => selectedChainIds.has(c.chainId))
  }, [contracts, selectedChainIds])

  // Initialize all contracts as selected when dialog opens
  useEffect(() => {
    if (isExportDialogOpen) {
      setSelectedContractIds(new Set(filteredContracts.map((c) => c.id)))
    }
  }, [isExportDialogOpen, filteredContracts])

  const handleExportClick = () => {
    if (contracts.length === 0) {
      toast.error("No contracts to export")
      return
    }
    setIsExportDialogOpen(true)
  }

  const handleExport = () => {
    if (selectedContractIds.size === 0) {
      toast.error("Please select at least one contract to export")
      return
    }
    exportContracts(Array.from(selectedContractIds))
    setIsExportDialogOpen(false)
    toast.success(
      `Successfully exported ${selectedContractIds.size} contract${selectedContractIds.size > 1 ? "s" : ""}`
    )
  }

  const toggleContractSelection = (contractId: string) => {
    setSelectedContractIds((prev) => {
      const next = new Set(prev)
      if (next.has(contractId)) {
        next.delete(contractId)
      } else {
        next.add(contractId)
      }
      return next
    })
  }

  const handleSelectAll = () => {
    if (selectedContractIds.size === filteredContracts.length) {
      setSelectedContractIds(new Set())
    } else {
      setSelectedContractIds(new Set(filteredContracts.map((c) => c.id)))
    }
  }

  const handleImportClick = () => {
    fileInputRef.current?.click()
  }

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    setIsImporting(true)
    try {
      const text = await file.text()
      const result = importContracts(text)

      if (result.success) {
        if (result.imported > 0) {
          toast.success(
            `Successfully imported ${result.imported} contract${result.imported > 1 ? "s" : ""}`
          )
        }
        if (result.errors.length > 0) {
          toast.warning(
            `Import completed with ${result.errors.length} warning${result.errors.length > 1 ? "s" : ""}`,
            {
              description: result.errors.slice(0, 3).join(", "),
            }
          )
        }
      } else {
        toast.error("Failed to import contracts", {
          description: result.errors[0],
        })
      }
    } catch (error) {
      toast.error("Failed to read file", {
        description: error instanceof Error ? error.message : "Unknown error",
      })
    } finally {
      setIsImporting(false)
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ""
      }
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Manage Contracts</h2>
          <p className="text-muted-foreground">
            View and manage your saved contracts
          </p>
        </div>
        <div className="flex gap-2">
          {contracts.length > 0 && (
            <Button variant="outline" onClick={handleExportClick}>
              <Download className="mr-2 size-4" />
              Export Contracts
            </Button>
          )}
          <Button variant="outline" onClick={handleImportClick} disabled={isImporting}>
            <Upload className="mr-2 size-4" />
            Load Contracts from File
          </Button>
          <input
            ref={fileInputRef}
            type="file"
            accept=".json,application/json"
            onChange={handleFileChange}
            className="hidden"
          />
        </div>
      </div>

      {contracts.length > 0 && (
        <ChainFilter
          selectedChainIds={selectedChainIds}
          onSelectionChange={setSelectedChainIds}
          availableChainIds={availableChainIds}
        />
      )}

      <Dialog open={isExportDialogOpen} onOpenChange={setIsExportDialogOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Export Contracts</DialogTitle>
            <DialogDescription>
              Select the contracts you want to export. All contracts are selected by default.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-3">
              <ChainFilter
                selectedChainIds={selectedChainIds}
                onSelectionChange={setSelectedChainIds}
                availableChainIds={availableChainIds}
              />
              <div className="flex items-center justify-between">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectAll}
                >
                  {selectedContractIds.size === filteredContracts.length
                    ? "Deselect All"
                    : "Select All"}
                </Button>
                <span className="text-sm text-muted-foreground">
                  {selectedContractIds.size} of {filteredContracts.length} selected
                </span>
              </div>
            </div>
            <ScrollArea className="h-[400px] rounded-md border p-4">
              <div className="space-y-3">
                {filteredContracts.map((contract) => (
                  <div
                    key={contract.id}
                    className="flex items-start gap-3 rounded-lg border p-3 hover:bg-accent/50 transition-colors"
                  >
                    <Checkbox
                      checked={selectedContractIds.has(contract.id)}
                      onChange={() => toggleContractSelection(contract.id)}
                      className="mt-0.5"
                    />
                    <div className="flex-1 space-y-2">
                      <div className="flex items-start justify-between">
                        <div>
                          <h4 className="font-medium">{contract.name}</h4>
                          <div className="flex items-center gap-2 mt-1">
                            <Badge variant="secondary">
                              {getContractTypeLabel(contract.type)}
                            </Badge>
                            <ChainBadge chainId={contract.chainId} size="sm" />
                          </div>
                        </div>
                      </div>
                      <div className="text-sm">
                        <CopyableAddress
                          address={contract.address}
                          truncateChars={8}
                          variant="code"
                          size="sm"
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setIsExportDialogOpen(false)}
            >
              Cancel
            </Button>
            <Button
              onClick={handleExport}
              disabled={selectedContractIds.size === 0}
            >
              Export {selectedContractIds.size > 0 && `(${selectedContractIds.size})`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {contracts.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <FileCode className="mb-4 size-12 text-muted-foreground" />
            <h3 className="text-lg font-medium">No contracts yet</h3>
            <p className="mb-4 text-center text-sm text-muted-foreground">
              Add your first contract to start interacting with the Open
              Coverage system.
            </p>
            <Button asChild>
              <Link to="/add-contract">Add Contract</Link>
            </Button>
          </CardContent>
        </Card>
      ) : filteredContracts.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <FileCode className="mb-4 size-12 text-muted-foreground" />
            <h3 className="text-lg font-medium">No contracts match filter</h3>
            <p className="mb-4 text-center text-sm text-muted-foreground">
              Try adjusting your chain filter to see more contracts.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          {filteredContracts.map((contract) => (
            <ContractCard key={contract.id} contract={contract} />
          ))}
        </div>
      )}
    </div>
  )
}
