import { Link } from "react-router-dom"
import { FileCode } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { useContracts } from "@/hooks/use-contracts"
import { ContractCard } from "@/components/ContractCard"

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
        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          {contracts.map((contract) => (
            <ContractCard key={contract.id} contract={contract} />
          ))}
        </div>
      )}
    </div>
  )
}
