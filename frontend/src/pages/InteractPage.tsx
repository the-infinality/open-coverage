import { useMemo } from "react"
import { Link, useNavigate, useParams } from "react-router-dom"

import { Button } from "@/components/ui/button"
import { useContracts } from "@/hooks/use-contracts"
import { ContractSelector } from "@/components/ContractSelector"
import { ContractSpecificInteractions } from "@/components/contract-specific-interactions"
import { FunctionCard } from "@/components/FunctionCard"

export function InteractPage() {
  const { contractId } = useParams<{ contractId?: string }>()
  const { contracts, getContractById } = useContracts()
  const navigate = useNavigate()

  // Derive selected contract directly from route parameter
  const selectedContract = useMemo(() => {
    if (contractId) {
      return getContractById(contractId) || null
    }
    return null
  }, [contractId, getContractById])

  if (contracts.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <h2 className="text-lg font-medium">No contracts yet</h2>
        <p className="mb-4 text-center text-sm text-muted-foreground">
          Add a contract to start interacting.
        </p>
        <Button asChild>
          <Link to="/add-contract">Add Contract</Link>
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Contract Interaction</h2>
        <p className="text-muted-foreground">
          Read and write to your contracts
        </p>
      </div>

      <ContractSelector
        title="Select Contract"
        description="Choose a contract to interact with"
        contractId={contractId}
        onContractChange={(contractId: string | null) => {
          if (contractId === null) navigate("/interact");
          navigate(`/interact/${contractId}`);
        }}
      />

      {selectedContract && (
        <>
          <ContractSpecificInteractions contract={selectedContract} />
          <FunctionCard contract={selectedContract} />
        </>
      )}
    </div>
  );
}
