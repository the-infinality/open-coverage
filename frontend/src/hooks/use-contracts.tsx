import * as React from "react"
import type { CoverageContract, ContractType } from "@/types/contracts"
import {
  getStoredContracts,
  saveContract as storeSaveContract,
  removeContract as storeRemoveContract,
  generateContractId,
} from "@/store/contracts"

interface ContractsContextValue {
  contracts: CoverageContract[]
  addContract: (contract: Omit<CoverageContract, "id" | "createdAt">) => CoverageContract
  updateContract: (id: string, updates: Partial<CoverageContract>) => void
  removeContract: (id: string) => void
  getContractById: (id: string) => CoverageContract | undefined
  getContractsByType: (type: ContractType) => CoverageContract[]
}

const ContractsContext = React.createContext<ContractsContextValue | undefined>(
  undefined
)

export function ContractsProvider({ children }: { children: React.ReactNode }) {
  const [contracts, setContracts] = React.useState<CoverageContract[]>(() =>
    getStoredContracts()
  )

  const addContract = React.useCallback(
    (contract: Omit<CoverageContract, "id" | "createdAt">) => {
      const newContract: CoverageContract = {
        ...contract,
        id: generateContractId(contract.chainId, contract.address),
        createdAt: Date.now(),
      }
      storeSaveContract(newContract)
      setContracts((prev) => [...prev, newContract])
      return newContract
    },
    []
  )

  const updateContract = React.useCallback(
    (id: string, updates: Partial<CoverageContract>) => {
      setContracts((prev) => {
        const updated = prev.map((c) =>
          c.id === id ? { ...c, ...updates } : c
        )
        const contract = updated.find((c) => c.id === id)
        if (contract) {
          storeSaveContract(contract)
        }
        return updated
      })
    },
    []
  )

  const removeContract = React.useCallback((id: string) => {
    storeRemoveContract(id)
    setContracts((prev) => prev.filter((c) => c.id !== id))
  }, [])

  const getContractById = React.useCallback(
    (id: string) => contracts.find((c) => c.id === id),
    [contracts]
  )

  const getContractsByType = React.useCallback(
    (type: ContractType) => contracts.filter((c) => c.type === type),
    [contracts]
  )

  const value: ContractsContextValue = {
    contracts,
    addContract,
    updateContract,
    removeContract,
    getContractById,
    getContractsByType,
  }

  return (
    <ContractsContext.Provider value={value}>
      {children}
    </ContractsContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useContracts() {
  const context = React.useContext(ContractsContext)
  if (!context) {
    throw new Error("useContracts must be used within ContractsProvider")
  }
  return context
}
