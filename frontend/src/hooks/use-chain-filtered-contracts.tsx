import { useMemo } from "react"
import { useContracts } from "@/hooks/use-contracts"
import type { CoverageContract } from "@/types/contracts"

/**
 * Hook to filter saved contracts by chain and type
 */
export function useChainFilteredContracts(chainId: number) {
  const { contracts } = useContracts()

  const serviceManagers = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === chainId && 
             c.type === "CoverageProvider"
    )
  }, [contracts, chainId])

  const coverageAgents = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === chainId && c.type === "CoverageAgent"
    )
  }, [contracts, chainId])

  const operatorProxies = useMemo(() => {
    return contracts.filter(
      (c) => c.chainId === chainId && c.type === "EigenOperatorProxy"
    )
  }, [contracts, chainId])

  return { serviceManagers, coverageAgents, operatorProxies }
}

/**
 * Hook to get available coverage providers for registration
 * Filters saved CoverageProvider contracts by chain, excluding specified contract IDs
 */
export function useAvailableCoverageProviders(
  chainId: number, 
  excludeIds: string[] = []
) {
  const { contracts } = useContracts()

  const availableProviders = useMemo(() => {
    const excludeSet = new Set(excludeIds)
    return contracts.filter(
      (c) => 
        c.type === "CoverageProvider" && 
        c.chainId === chainId &&
        !excludeSet.has(c.id)
    )
  }, [contracts, chainId, excludeIds])

  return { availableProviders }
}

/**
 * Helper to get the selected provider from a list of providers by ID
 */
export function getSelectedProvider(
  selectedId: string,
  providers: CoverageContract[]
): CoverageContract | null {
  if (!selectedId) return null
  return providers.find(p => p.id === selectedId) || null
}

/**
 * Helper to get the selected coverage agent from a list by ID
 */
export function getSelectedCoverageAgent(
  selectedId: string,
  coverageAgents: CoverageContract[]
): CoverageContract | null {
  if (!selectedId) return null
  return coverageAgents.find(ca => ca.id === selectedId) || null
}

/**
 * Helper to get the selected operator proxy from a list by ID
 */
export function getSelectedOperatorProxy(
  selectedId: string,
  operatorProxies: CoverageContract[]
): CoverageContract | null {
  if (!selectedId) return null
  return operatorProxies.find(op => op.id === selectedId) || null
}

