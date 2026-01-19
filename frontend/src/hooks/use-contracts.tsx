import * as React from "react"
import type { CoverageContract, ContractType } from "@/types/contracts"
import {
    getStoredContracts,
    saveContract as storeSaveContract,
    removeContract as storeRemoveContract,
    generateContractId,
    exportContractsToJson,
    importContractsFromJson,
} from "@/store/contracts"

interface ContractsContextValue {
    contracts: CoverageContract[]
    addContract: (contract: Omit<CoverageContract, "id" | "createdAt">) => CoverageContract
    updateContract: (id: string, updates: Partial<CoverageContract>) => void
    removeContract: (id: string) => void
    getContractById: (id: string) => CoverageContract | undefined
    getContractsByType: (type: ContractType) => CoverageContract[]
    exportContracts: (contractIds?: string[]) => void
    importContracts: (
        json: string,
        overwrite?: boolean
    ) => { success: boolean; imported: number; updated: number; errors: string[] }
}

const ContractsContext = React.createContext<ContractsContextValue | undefined>(undefined)

export function ContractsProvider({ children }: { children: React.ReactNode }) {
    const [contracts, setContracts] = React.useState<CoverageContract[]>(() => getStoredContracts())

    const addContract = React.useCallback(
        (contract: Omit<CoverageContract, "id" | "createdAt">) => {
            const contractId = generateContractId(contract.chainId, contract.address)

            let newContract: CoverageContract
            setContracts((prev) => {
                const existingContract = prev.find((c) => c.id === contractId)
                newContract = {
                    ...contract,
                    id: contractId,
                    createdAt: existingContract?.createdAt || Date.now(),
                }

                storeSaveContract(newContract)

                const existing = prev.findIndex((c) => c.id === contractId)
                if (existing >= 0) {
                    const updated = [...prev]
                    updated[existing] = newContract
                    return updated
                }
                return [...prev, newContract]
            })
            return newContract!
        },
        []
    )

    const updateContract = React.useCallback((id: string, updates: Partial<CoverageContract>) => {
        setContracts((prev) => {
            const updated = prev.map((c) => (c.id === id ? { ...c, ...updates } : c))
            const contract = updated.find((c) => c.id === id)
            if (contract) {
                storeSaveContract(contract)
            }
            return updated
        })
    }, [])

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

    const exportContracts = React.useCallback((contractIds?: string[]) => {
        const json = exportContractsToJson(contractIds)
        const blob = new Blob([json], { type: "application/json" })
        const url = URL.createObjectURL(blob)
        const link = document.createElement("a")
        link.href = url
        // Format: contracts-YYYY-MM-DD_HH-MM-SS.json
        const timestamp = new Date()
            .toISOString()
            .replace(/T/, "_")
            .replace(/[:.]/g, "-")
            .slice(0, -5)
        link.download = `contracts-${timestamp}.json`
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
        URL.revokeObjectURL(url)
    }, [])

    const importContracts = React.useCallback((json: string, overwrite: boolean = false) => {
        const result = importContractsFromJson(json, overwrite)
        if (result.success) {
            // Refresh contracts from storage
            setContracts(getStoredContracts())
        }
        return result
    }, [])

    const value: ContractsContextValue = {
        contracts,
        addContract,
        updateContract,
        removeContract,
        getContractById,
        getContractsByType,
        exportContracts,
        importContracts,
    }

    return <ContractsContext.Provider value={value}>{children}</ContractsContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useContracts() {
    const context = React.useContext(ContractsContext)
    if (!context) {
        throw new Error("useContracts must be used within ContractsProvider")
    }
    return context
}
