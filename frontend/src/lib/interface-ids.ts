// Interface IDs (computed as XOR of all function selectors)
// These are derived from the Solidity interfaces using ERC-165
export const INTERFACE_IDS = {
    IEigenServiceManager: "0xb4869c7d" as const,
    IAssetPriceOracleAndSwapper: "0x9fa992e8" as const,
    ICoverageProvider: "0xcc30c1ff" as const,
    IDiamondOwner: "0x9e0a8b6e" as const,
    IExampleCoverageAgent: "0xc48cc274" as const,
    ICoverageAgent: "0x36591e27" as const,
} as const

export type InterfaceName = keyof typeof INTERFACE_IDS
