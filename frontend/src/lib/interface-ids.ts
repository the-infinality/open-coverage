// Interface IDs (computed as XOR of all function selectors)
// These are derived from the Solidity interfaces using ERC-165
export const INTERFACE_IDS = {
  // IEigenServiceManager interface ID
  IEigenServiceManager: "0x7e0b1fe6" as const,
  // IAssetPriceOracleAndSwapper interface ID  
  IAssetPriceOracleAndSwapper: "0x9fa992e8" as const,
  // ICoverageProvider interface ID
  ICoverageProvider: "0x455485e4" as const,
} as const

export type InterfaceName = keyof typeof INTERFACE_IDS

