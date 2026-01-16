import type { CoverageContract } from "@/types/contracts"
import { EigenOperatorProxyManagement } from "./EigenOperatorProxyManagement"
import { CoverageAgentInfo } from "./CoverageAgentInfo"

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

  // For other contract types, return null for now
  // Can be extended later for CoverageProvider or other types
  return null
}

