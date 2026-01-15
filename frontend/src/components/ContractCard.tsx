import React, { useState } from "react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { Trash2, ExternalLink, FileCode, Plus, Pencil } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useContracts } from "@/hooks/use-contracts";
import { getContractTypeLabel } from "@/lib/contract-utils";
import { generateContractName } from "@/lib/utils";
import { CopyableAddress } from "@/components/ui/copyable-address";
import { ChainBadge } from "@/components/ui/chain-badge";
import { Badge } from "@/components/ui/badge";
import type { CoverageContract } from "@/types/contracts";

interface ContractCardProps {
  contract: Omit<CoverageContract, "id" | "createdAt" | "name"> & {
    name?: string;
    id?: string;
    createdAt?: number;
  };
}

export const ContractCard: React.FC<ContractCardProps> = ({
  contract,
}) => {
  const { removeContract, addContract, updateContract, contracts } = useContracts();
  const unsaved = !contract.name;
  // Automatically open dialog if unsaved and name is missing
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false);
  
  // Generate default contract name if not provided
  const [contractName, setContractName] = useState(() => {
    if (contract.name) return contract.name;
    if (contract.type) return generateContractName(contract.type, contracts);
    return "";
  });

  // State for editing contract name
  const [editName, setEditName] = useState(contract.name || "");

  // Reset to generated name when dialog opens
  const handleDialogOpenChange = (open: boolean) => {
    setIsAddDialogOpen(open);
    if (open && !contract.name && contract.type) {
      const generatedName = generateContractName(contract.type, contracts);
      setContractName(generatedName);
    }
  };

  const handleDelete = () => {
    setIsDeleteDialogOpen(false);
    if (contract.id) {
      removeContract(contract.id);
      toast.success("Contract removed");
    }
  };

  const handleAddContract = () => {
    if (!contractName.trim()) {
      toast.error("Please enter a contract name");
      return;
    }

    try {
      addContract({
        ...contract,
        name: contractName.trim(),
      });
      setIsAddDialogOpen(false);
      toast.success("Contract added successfully");
    } catch {
      toast.error("Failed to add contract");
    }
  };

  const handleEditName = () => {
    if (!contract.id) return;
    
    if (!editName.trim()) {
      toast.error("Please enter a contract name");
      return;
    }

    try {
      updateContract(contract.id, { name: editName.trim() });
      setIsEditDialogOpen(false);
      toast.success("Contract name updated");
    } catch {
      toast.error("Failed to update contract name");
    }
  };

  const handleEditDialogOpenChange = (open: boolean) => {
    setIsEditDialogOpen(open);
    if (open && contract.name) {
      setEditName(contract.name);
    }
  };

  return (
    <>
      <Card className="gap-4">
        <CardHeader className="gap-0">
          <div className="flex items-start justify-between">
            <div className="flex flex-col gap-y-0 flex-1 min-w-0">
              {contract.name && (
                <div className="flex items-center gap-2 group">
                  <CardTitle className="text-lg truncate">{contract.name}</CardTitle>
                  {!unsaved && contract.id && (
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                      onClick={() => setIsEditDialogOpen(true)}
                    >
                      <Pencil className="size-3" />
                    </Button>
                  )}
                </div>
              )}
              <CardDescription className="flex items-center gap-x-2 flex-wrap">
                <Badge variant="secondary">
                  {getContractTypeLabel(contract.type)}
                </Badge>
                <ChainBadge chainId={contract.chainId} size="sm" />
              </CardDescription>
            </div>
            {!unsaved && (
              <Button variant="ghost" size="icon" className="text-destructive shrink-0" onClick={() => setIsDeleteDialogOpen(true)}>
                <Trash2 className="size-4" />
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between text-sm gap-2">
            <span className="text-muted-foreground">Address</span>
            <CopyableAddress
              address={contract.address}
              truncateChars={6}
              variant="code"
              size="sm"
            />
          </div>
          {unsaved ? (
            <div className="flex gap-2 pt-2">
              <Button
                variant="default"
                size="sm"
                className="flex-1"
                onClick={() => setIsAddDialogOpen(true)}
              >
                <Plus className="mr-2 size-4" />
                Add Contract
              </Button>
            </div>
          ) : contract.id ? (
            <div className="flex gap-2 pt-2">
              <Button variant="outline" size="sm" asChild className="flex-1">
                <Link to={`/interact/${contract.id}`}>
                  <FileCode className="mr-2 size-4" />
                  Interact
                </Link>
              </Button>
              <Button variant="outline" size="sm" asChild className="flex-1">
                <Link to={`/logs/${contract.id}`}>
                  <ExternalLink className="mr-2 size-4" />
                  Logs
                </Link>
              </Button>
            </div>
          ) : null}
        </CardContent>
      </Card>
      {unsaved ? (
        <Dialog open={isAddDialogOpen} onOpenChange={handleDialogOpenChange}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Contract</DialogTitle>
              <DialogDescription>
                Enter a name for this contract to save it to your collection.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="contract-name">Contract Name</Label>
                <Input
                  id="contract-name"
                  placeholder="e.g., My Coverage Provider"
                  value={contractName}
                  onChange={(e) => setContractName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      handleAddContract();
                    }
                  }}
                />
              </div>
              <div className="space-y-2 text-sm text-muted-foreground">
                <div className="flex items-center justify-between">
                  <span>Address:</span>
                  <code className="rounded bg-muted px-2 py-1 text-xs font-mono">
                    {contract.address}
                  </code>
                </div>
                <div className="flex items-center justify-between">
                  <span>Type:</span>
                  <span>{getContractTypeLabel(contract.type)}</span>
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => setIsAddDialogOpen(false)}
              >
                Cancel
              </Button>
              <Button
                onClick={handleAddContract}
                disabled={!contractName.trim()}
              >
                Add Contract
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      ) : (
        <>
          <Dialog open={isEditDialogOpen} onOpenChange={handleEditDialogOpenChange}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Rename Contract</DialogTitle>
                <DialogDescription>
                  Enter a new name for this contract.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label htmlFor="edit-contract-name">Contract Name</Label>
                  <Input
                    id="edit-contract-name"
                    placeholder="e.g., My Coverage Provider"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        handleEditName();
                      }
                    }}
                  />
                </div>
              </div>
              <DialogFooter>
                <Button
                  variant="outline"
                  onClick={() => setIsEditDialogOpen(false)}
                >
                  Cancel
                </Button>
                <Button
                  onClick={handleEditName}
                  disabled={!editName.trim()}
                >
                  Save
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
          <Dialog open={isDeleteDialogOpen} onOpenChange={setIsDeleteDialogOpen}>
            <DialogTrigger asChild>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Remove Contract</DialogTitle>
                <DialogDescription>
                  Are you sure you want to remove "{contract.name}"? This action
                  cannot be undone.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" onClick={() => setIsDeleteDialogOpen(false)}>
                  Cancel
                </Button>
                <Button variant="destructive" onClick={handleDelete}>
                  Remove
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </>
      )}
    </>
  );
};
