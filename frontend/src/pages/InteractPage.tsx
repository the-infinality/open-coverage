import { useMemo } from "react"
import { Link, useNavigate, useParams } from "react-router-dom"
import { type Abi, type AbiFunction } from "viem"

import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"
import { useContracts } from "@/hooks/use-contracts"
import { getAbiForContractType } from "@/lib/abi"
import { ContractSelector } from "@/components/ContractSelector"
import { ContractSpecificInfo } from "@/components/ContractSpecificInfo"
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

  const abi = useMemo(
    () =>
      selectedContract
        ? (getAbiForContractType(selectedContract.type) as Abi)
        : [],
    [selectedContract]
  )

  const readFunctions = useMemo(
    () =>
      abi.filter(
        (item): item is AbiFunction =>
          item.type === "function" &&
          (item.stateMutability === "view" || item.stateMutability === "pure")
      ),
    [abi]
  )

  const writeFunctions = useMemo(
    () =>
      abi.filter(
        (item): item is AbiFunction =>
          item.type === "function" &&
          item.stateMutability !== "view" &&
          item.stateMutability !== "pure"
      ),
    [abi]
  )

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
          if(contractId === null) navigate('/interact')
          navigate(`/interact/${contractId}`)
        }}
      />

      {selectedContract && (
        <>
          <ContractSpecificInfo contract={selectedContract} />
          <Card className="h-fit">
          <CardHeader>
            <CardTitle>Contract Functions</CardTitle>
            <CardDescription>
              Read and write functions for {selectedContract.name}
            </CardDescription>
          </CardHeader>
          <CardContent className="h-fit">
            <Tabs defaultValue="read" key={contractId}>
              <TabsList className="w-full">
                <TabsTrigger value="read" className="flex-1">
                  Read ({readFunctions.length})
                </TabsTrigger>
                <TabsTrigger value="write" className="flex-1">
                  Write ({writeFunctions.length})
                </TabsTrigger>
              </TabsList>
              <TabsContent value="read" className="mt-4">
                <ScrollArea className="h-fit">
                  <div className="divide-y rounded-lg border">
                    {readFunctions.map((fn, index) => (
                      <FunctionCard
                        key={index}
                        fn={fn}
                        contractAddress={selectedContract.address}
                        abi={abi}
                        chainId={selectedContract.chainId}
                      />
                    ))}
                  </div>
                </ScrollArea>
              </TabsContent>
              <TabsContent value="write" className="mt-4">
                <ScrollArea className="h-fit">
                  <div className="divide-y rounded-lg border">
                    {writeFunctions.map((fn, index) => (
                      <FunctionCard
                        key={index}
                        fn={fn}
                        contractAddress={selectedContract.address}
                        abi={abi}
                        chainId={selectedContract.chainId}
                      />
                    ))}
                  </div>
                </ScrollArea>
              </TabsContent>
            </Tabs>
          </CardContent>
        </Card>
        </>
      )}
    </div>
  )
}
