import { useMemo } from "react"
import { type Address } from "viem"
import { RefreshCw, Loader2 } from "lucide-react"
import { useReadContract } from "wagmi"
import type { CoverageContract } from "@/types/contracts"
import { iCoverageAgentAbi } from "@/generated/abis"
import { ContractCard } from "@/components/ContractCard"
import { useContracts } from "@/hooks/use-contracts"
import { supportedChains } from "@/lib/wagmi"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"

interface CoverageAgentInfoProps {
  contract: CoverageContract
}

export function CoverageAgentInfo({ contract }: CoverageAgentInfoProps) {
  const { contracts } = useContracts()

  // Check if chainId is supported
  const isChainSupported = supportedChains.some(
    (chain) => chain.id === contract.chainId
  )

  const {
    data: coverageProviders,
    isLoading,
    isError,
    refetch,
  } = useReadContract({
    address: contract.address,
    abi: iCoverageAgentAbi,
    functionName: "registeredCoverageProviders",
    chainId: isChainSupported
      ? (contract.chainId as (typeof supportedChains)[number]["id"])
      : undefined,
    query: {
      enabled: isChainSupported,
    },
  })

  // Create a map of saved contracts by address for quick lookup
  const savedContractsMap = useMemo(() => {
    const map = new Map<string, CoverageContract>()
    contracts.forEach((c) => {
      const key = `${c.chainId}-${c.address.toLowerCase()}`
      map.set(key, c)
    })
    return map
  }, [contracts])

  // Convert the result to Address[] array
  const providers = useMemo(() => {
    if (!coverageProviders) return []
    return [...(coverageProviders as Address[])]
  }, [coverageProviders])

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Registered Coverage Providers</CardTitle>
            <CardDescription>
              Coverage providers registered with this agent
            </CardDescription>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => refetch()}
            disabled={isLoading}
          >
            {isLoading ? (
              <Loader2 className="mr-2 size-4 animate-spin" />
            ) : (
              <RefreshCw className="mr-2 size-4" />
            )}
            Refresh
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading && providers.length === 0 ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : isError ? (
          <div className="py-8 text-center text-sm text-destructive">
            Failed to fetch coverage providers
          </div>
        ) : providers.length === 0 ? (
          <div className="py-8 text-center text-sm text-muted-foreground">
            No coverage providers registered yet
          </div>
        ) : (
          <ScrollArea className="h-fit max-h-[400px]">
            <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
              {providers.map((providerAddress) => {
                const contractKey = `${contract.chainId}-${providerAddress.toLowerCase()}`
                const savedContract = savedContractsMap.get(contractKey)
                
                return (
                  <ContractCard
                    key={providerAddress}
                    contract={
                      savedContract || {
                        address: providerAddress,
                        type: "CoverageProvider",
                        chainId: contract.chainId,
                      }
                    }
                  />
                )
              })}
            </div>
          </ScrollArea>
        )}
      </CardContent>
    </Card>
  )
}

