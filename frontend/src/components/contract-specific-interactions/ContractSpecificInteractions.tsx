import type { CoverageContract } from "@/types/contracts"
import { EigenOperatorProxyManagement } from "./EigenOperatorProxyManagement"
import { EigenProviderOperatorManagement } from "./EigenProviderOperatorManagement"
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

  // Show operator management for EigenLayer providers
  if (
    contract.type === "CoverageProvider" && 
    contract.additionalFields?.providerType === "EigenLayer"
  ) {
    return <EigenProviderOperatorManagement contract={contract} />
  }

  // For other contract types, return null for now
  return null
}

