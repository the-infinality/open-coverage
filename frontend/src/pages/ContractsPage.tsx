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
import { Label } from "@/components/ui/label"
import { useContracts } from "@/hooks/use-contracts"
import { ContractCard } from "@/components/ContractCard"
import { getContractTypeLabel } from "@/lib/contract-utils"
import { CopyableAddress } from "@/components/ui/copyable-address"
import { ChainBadge } from "@/components/ui/chain-badge"
import { Badge } from "@/components/ui/badge"
import { ChainFilter } from "@/components/ChainFilter"
import { ContractTypeFilter } from "@/components/ContractTypeFilter"
import type { ContractType } from "@/types/contracts"

export function ContractsPage() {
  const { contracts, exportContracts, importContracts } = useContracts()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [isImporting, setIsImporting] = useState(false)
  const [isExportDialogOpen, setIsExportDialogOpen] = useState(false)
  const [isImportDialogOpen, setIsImportDialogOpen] = useState(false)
  const [importFileContent, setImportFileContent] = useState<string | null>(null)
  const [overwriteExisting, setOverwriteExisting] = useState(false)
  const [selectedContractIds, setSelectedContractIds] = useState<Set<string>>(
    new Set()
  )
  const [selectedChainIds, setSelectedChainIds] = useState<Set<number>>(
    new Set()
  )
  const [selectedContractTypes, setSelectedContractTypes] = useState<Set<ContractType>>(
    new Set()
  )

  // Get unique chain IDs from contracts
  const availableChainIds = useMemo(() => {
    return Array.from(new Set(contracts.map((c) => c.chainId)))
  }, [contracts])

  // Get unique contract types from contracts
  const availableContractTypes = useMemo(() => {
    return Array.from(new Set(contracts.map((c) => c.type))) as ContractType[]
  }, [contracts])

  // Clean up chain selections when available chains change (e.g., contract deleted)
  useEffect(() => {
    if (availableChainIds.length === 0 || selectedChainIds.size === 0) return

    // Update selection to only include available chains
    const validChainIds = availableChainIds.filter((id) =>
      selectedChainIds.has(id)
    )
    if (validChainIds.length !== selectedChainIds.size) {
      // Some selected chains are no longer available, update selection
      setSelectedChainIds(new Set(validChainIds))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [availableChainIds])

  // Clean up contract type selections when available types change
  useEffect(() => {
    if (availableContractTypes.length === 0 || selectedContractTypes.size === 0) return

    // Update selection to only include available types
    const validTypes = availableContractTypes.filter((type) =>
      selectedContractTypes.has(type)
    )
    if (validTypes.length !== selectedContractTypes.size) {
      // Some selected types are no longer available, update selection
      setSelectedContractTypes(new Set(validTypes))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [availableContractTypes])

  // Filter contracts by selected chains and contract types
  const filteredContracts = useMemo(() => {
    return contracts.filter((c) => {
      const chainMatch = selectedChainIds.size === 0 || selectedChainIds.has(c.chainId)
      const typeMatch = selectedContractTypes.size === 0 || selectedContractTypes.has(c.type)
      return chainMatch && typeMatch
    })
  }, [contracts, selectedChainIds, selectedContractTypes])

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

    try {
      const text = await file.text()
      setImportFileContent(text)
      setIsImportDialogOpen(true)
    } catch (error) {
      toast.error("Failed to read file", {
        description: error instanceof Error ? error.message : "Unknown error",
      })
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ""
      }
    }
  }

  const handleImportConfirm = async () => {
    if (!importFileContent) return

    setIsImporting(true)
    setIsImportDialogOpen(false)
    try {
      const result = importContracts(importFileContent, overwriteExisting)

      if (result.success) {
        const messages: string[] = []
        if (result.imported > 0) {
          messages.push(
            `Imported ${result.imported} new contract${result.imported > 1 ? "s" : ""}`
          )
        }
        if (result.updated > 0) {
          messages.push(
            `Updated ${result.updated} existing contract${result.updated > 1 ? "s" : ""}`
          )
        }
        if (messages.length > 0) {
          toast.success(messages.join(", "))
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
      toast.error("Failed to import contracts", {
        description: error instanceof Error ? error.message : "Unknown error",
      })
    } finally {
      setIsImporting(false)
      setImportFileContent(null)
      setOverwriteExisting(false)
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = ""
      }
    }
  }

  const handleImportDialogClose = () => {
    setIsImportDialogOpen(false)
    setImportFileContent(null)
    setOverwriteExisting(false)
    // Reset file input
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-2.5 flex-wrap">
        <div className="min-w-[300px]">
          <h2 className="text-2xl font-bold">Manage Contracts</h2>
          <p className="text-muted-foreground">
            View and manage your saved contracts
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          {contracts.length > 0 && (
            <Button variant="outline" onClick={handleExportClick}>
              <Download className="mr-2 size-4" />
              Export Contracts
            </Button>
          )}
          <Button variant="outline" onClick={() => setIsImportDialogOpen(true)} disabled={isImporting}>
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

      <Dialog open={isImportDialogOpen} onOpenChange={handleImportDialogClose}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Import Contracts</DialogTitle>
            <DialogDescription>
              {importFileContent
                ? "Choose how to handle contracts that already exist."
                : "Select a JSON file containing contracts to import."}
            </DialogDescription>
          </DialogHeader>
          {!importFileContent ? (
            <div className="space-y-4 py-4">
              <div className="flex flex-col items-center justify-center py-8 border-2 border-dashed rounded-lg">
                <Upload className="mb-4 size-12 text-muted-foreground" />
                <p className="text-sm text-muted-foreground mb-4">
                  Select a JSON file to import contracts
                </p>
                <Button onClick={handleImportClick} variant="outline">
                  Select File
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-4 py-4">
              <div className="flex items-start gap-3 rounded-lg border p-3">
                <Checkbox
                  checked={overwriteExisting}
                  onChange={() => setOverwriteExisting(!overwriteExisting)}
                  id="overwrite-existing"
                />
                <div className="flex-1 space-y-1">
                  <Label
                    htmlFor="overwrite-existing"
                    className="cursor-pointer font-medium"
                  >
                    Overwrite existing contracts
                  </Label>
                  <p className="text-sm text-muted-foreground">
                    If enabled, contracts with matching addresses and chain IDs will be
                    updated with data from the imported file. Otherwise, existing contracts
                    will be skipped.
                  </p>
                </div>
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={handleImportDialogClose}>
              Cancel
            </Button>
            {importFileContent && (
              <Button onClick={handleImportConfirm} disabled={isImporting}>
                {isImporting ? "Importing..." : "Import"}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {contracts.length > 0 && (
        <div className="flex flex-wrap gap-3">
          <ChainFilter
            selectedChainIds={selectedChainIds}
            onSelectionChange={setSelectedChainIds}
            availableChainIds={availableChainIds}
          />
          <ContractTypeFilter
            selectedTypes={selectedContractTypes}
            onSelectionChange={setSelectedContractTypes}
            availableTypes={availableContractTypes}
          />
        </div>
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
              <div className="flex flex-wrap gap-3">
                <ChainFilter
                  selectedChainIds={selectedChainIds}
                  onSelectionChange={setSelectedChainIds}
                  availableChainIds={availableChainIds}
                />
                <ContractTypeFilter
                  selectedTypes={selectedContractTypes}
                  onSelectionChange={setSelectedContractTypes}
                  availableTypes={availableContractTypes}
                />
              </div>
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
              Try adjusting your filters to see more contracts.
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
