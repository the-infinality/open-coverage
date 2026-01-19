import type { CoverageContract } from "@/types/contracts"
import { EigenOperatorProxyManagement } from "./EigenOperatorProxyManagement"
import { CoverageAgentInfo } from "./CoverageAgentInfo"
import { CoverageProviderInfo } from "./CoverageProviderInfo"

interface ContractSpecificInteractionsProps {
    contract: CoverageContract
}

export function ContractSpecificInteractions({ contract }: ContractSpecificInteractionsProps) {
    if (contract.type === "CoverageAgent") {
        return <CoverageAgentInfo contract={contract} />
    }

    if (contract.type === "EigenOperatorProxy") {
        return <EigenOperatorProxyManagement contract={contract} />
    }

    if (contract.type === "CoverageProvider") {
        return <CoverageProviderInfo contract={contract} />
    }

    // For other contract types, return null for now
    return null
}
