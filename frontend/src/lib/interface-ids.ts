// Interface IDs (computed as XOR of all function selectors)
// These are derived from the Solidity interfaces using ERC-165
export const INTERFACE_IDS = {
    IEigenServiceManager: "0xe77ba2fc" as const,
    IAssetPriceOracleAndSwapper: "0x9fa992e8" as const,
    ICoverageProvider: "0xcc30c1ff" as const,
    IDiamondOwner: "0x9e0a8b6e" as const,
} as const

export type InterfaceName = keyof typeof INTERFACE_IDS
