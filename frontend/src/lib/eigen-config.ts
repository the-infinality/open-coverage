/**
 * EigenLayer addresses configuration for contract deployment
 * Based on config/eigen.json
 */

export interface EigenAddresses {
  allocationManager: `0x${string}`
  delegationManager: `0x${string}`
  strategyManager: `0x${string}`
  rewardsCoordinator: `0x${string}`
  permissionController: `0x${string}`
}

export interface EigenConfig {
  [chainId: number]: EigenAddresses
}

/**
 * EigenLayer contract addresses by chain ID
 * 1 = Mainnet, 11155111 = Sepolia, 31337 = Local
 */
export const eigenConfig: EigenConfig = {
  // Ethereum Mainnet
  1: {
    allocationManager: "0x948a420b8CC1d6BFd0B6087C2E7c344a2CD0bc39",
    delegationManager: "0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A",
    strategyManager: "0x858646372CC42E1A627fcE94aa7A7033e7CF075A",
    rewardsCoordinator: "0x7750d328b314EfFa365A0402CcfD489B80B0adda",
    permissionController: "0x25E5F8B1E7aDf44518d35D5B2271f114e081f0E5",
  },
  // Sepolia Testnet
  11155111: {
    allocationManager: "0x42583067658071247ec8CE0A516A58f682002d07",
    delegationManager: "0xD4A7E1Bd8015057293f0D0A557088c286942e84b",
    strategyManager: "0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D",
    rewardsCoordinator: "0x5ae8152fb88c26ff9ca5C014c94fca3c68029349",
    permissionController: "0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37",
  },
  // Localhost / Anvil
  31337: {
    allocationManager: "0x42583067658071247ec8CE0A516A58f682002d07",
    delegationManager: "0xD4A7E1Bd8015057293f0D0A557088c286942e84b",
    strategyManager: "0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D",
    rewardsCoordinator: "0x5ae8152fb88c26ff9ca5C014c94fca3c68029349",
    permissionController: "0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37",
  },
}

/**
 * Get EigenLayer addresses for a specific chain
 */
export function getEigenAddresses(chainId: number): EigenAddresses | null {
  return eigenConfig[chainId] ?? null
}

/**
 * Check if EigenLayer is supported on a given chain
 */
export function isEigenLayerSupported(chainId: number): boolean {
  return chainId in eigenConfig
}
