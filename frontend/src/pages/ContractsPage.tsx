import { Link } from "react-router-dom"
import { toast } from "sonner"
import { Trash2, ExternalLink, FileCode } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { useContracts } from "@/hooks/use-contracts"
import { getContractTypeLabel } from "@/lib/contract-utils"
import { getChainName } from "@/lib/wagmi"
import { CopyableAddress } from "@/components/ui/copyable-address"
import type { SavedContract } from "@/types/contracts"

function ContractCard({ contract }: { contract: SavedContract }) {
  const { removeContract } = useContracts()

  const handleDelete = () => {
    removeContract(contract.id)
    toast.success("Contract removed")
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div>
            <CardTitle className="text-lg">{contract.name}</CardTitle>
            <CardDescription>
              {getContractTypeLabel(contract.type)} on{" "}
              {getChainName(contract.chainId)}
            </CardDescription>
          </div>
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="ghost" size="icon" className="text-destructive">
                <Trash2 className="size-4" />
              </Button>
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
                <Button variant="outline" onClick={() => {}}>
                  Cancel
                </Button>
                <Button variant="destructive" onClick={handleDelete}>
                  Remove
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Address</span>
          <CopyableAddress
            address={contract.address}
            truncateChars={6}
            variant="code"
            size="sm"
          />
        </div>
        {contract.ownerAddress && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Owner</span>
            <CopyableAddress
              address={contract.ownerAddress}
              truncateChars={6}
              variant="code"
              size="sm"
            />
          </div>
        )}
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Added</span>
          <span>{new Date(contract.createdAt).toLocaleDateString()}</span>
        </div>
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
      </CardContent>
    </Card>
  )
}

export function ContractsPage() {
  const { contracts } = useContracts()

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Manage Contracts</h2>
          <p className="text-muted-foreground">
            View and manage your saved contracts
          </p>
        </div>
      </div>

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
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {contracts.map((contract) => (
            <ContractCard key={contract.id} contract={contract} />
          ))}
        </div>
      )}
    </div>
  )
}
