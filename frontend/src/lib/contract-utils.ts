import type { ContractType } from "@/types/contracts"

// Helper function to convert contract type to display name
export function getContractTypeLabel(type: ContractType): string {
  switch (type) {
    case "CoverageAgent":
      return "Coverage Agent"
    case "CoverageProvider":
      return "Coverage Provider"
    case "EigenOperatorProxy":
      return "Eigen Operator Proxy"
    default:
      return type
  }
}

// Helper to get supported contract types
export function getContractTypes(): { value: ContractType; label: string }[] {
  return [
    { value: "CoverageAgent", label: "Coverage Agent" },
    { value: "CoverageProvider", label: "Coverage Provider" },
    { value: "EigenOperatorProxy", label: "Eigen Operator Proxy" },
  ]
}

