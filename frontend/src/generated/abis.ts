export const coverageAgentAbi = [
  {
    type: "function",
    name: "asset",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "coordinator",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "coverage",
    inputs: [{ name: "coverageId", type: "uint256", internalType: "uint256" }],
    outputs: [
      {
        name: "coverage",
        type: "tuple",
        internalType: "struct Coverage",
        components: [
          {
            name: "claims",
            type: "tuple[]",
            internalType: "struct Claim[]",
            components: [
              { name: "coverageProvider", type: "address", internalType: "address" },
              { name: "claimId", type: "uint256", internalType: "uint256" },
            ],
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isCoverageProviderRegistered",
    inputs: [{ name: "coverageProvider", type: "address", internalType: "address" }],
    outputs: [{ name: "isRegistered", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "onRegisterPosition",
    inputs: [{ name: "positionId", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "onSlashCompleted",
    inputs: [
      { name: "claimId", type: "uint256", internalType: "uint256" },
      { name: "slashAmount", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "registerCoverageProvider",
    inputs: [{ name: "coverageProvider", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "registeredCoverageProviders",
    inputs: [],
    outputs: [{ name: "coverageProviderAddresses", type: "address[]", internalType: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "CoverageClaimed",
    inputs: [{ name: "coverageId", type: "uint256", indexed: true, internalType: "uint256" }],
    anonymous: false,
  },
  {
    type: "event",
    name: "CoverageProviderRegistered",
    inputs: [{ name: "coverageProvider", type: "address", indexed: true, internalType: "address" }],
    anonymous: false,
  },
  {
    type: "event",
    name: "PositionRegistered",
    inputs: [
      { name: "coverageProvider", type: "address", indexed: true, internalType: "address" },
      { name: "positionId", type: "uint256", indexed: true, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "error",
    name: "InvalidCoverage",
    inputs: [{ name: "coverageId", type: "uint256", internalType: "uint256" }],
  },
] as const

export const coverageProviderAbi = [
  {
    type: "function",
    name: "claim",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [
      {
        name: "claim",
        type: "tuple",
        internalType: "struct CoverageClaim",
        components: [
          { name: "positionId", type: "uint256", internalType: "uint256" },
          { name: "amount", type: "uint256", internalType: "uint256" },
          { name: "duration", type: "uint256", internalType: "uint256" },
          { name: "createdAt", type: "uint256", internalType: "uint256" },
          { name: "status", type: "uint8", internalType: "enum CoverageClaimStatus" },
          { name: "reward", type: "uint256", internalType: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimBacking",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [{ name: "backing", type: "int256", internalType: "int256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimCoverage",
    inputs: [
      { name: "positionId", type: "uint256", internalType: "uint256" },
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "duration", type: "uint256", internalType: "uint256" },
      { name: "reward", type: "uint256", internalType: "uint256" },
    ],
    outputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "claimTotalSlashAmount",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [{ name: "slashAmount", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "closePosition",
    inputs: [{ name: "positionId", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "completeClaims",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "completeSlash",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "createPosition",
    inputs: [
      { name: "coverageAgent", type: "address", internalType: "address" },
      {
        name: "data",
        type: "tuple",
        internalType: "struct CoveragePosition",
        components: [
          { name: "coverageAgent", type: "address", internalType: "address" },
          { name: "minRate", type: "uint16", internalType: "uint16" },
          { name: "maxDuration", type: "uint256", internalType: "uint256" },
          { name: "expiryTimestamp", type: "uint256", internalType: "uint256" },
          { name: "asset", type: "address", internalType: "address" },
          { name: "refundable", type: "uint8", internalType: "enum Refundable" },
          { name: "slashCoordinator", type: "address", internalType: "address" },
        ],
      },
      { name: "additionalData", type: "bytes", internalType: "bytes" },
    ],
    outputs: [{ name: "positionId", type: "uint256", internalType: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "liquidateClaim",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "onIsRegistered",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "position",
    inputs: [{ name: "positionId", type: "uint256", internalType: "uint256" }],
    outputs: [
      {
        name: "position",
        type: "tuple",
        internalType: "struct CoveragePosition",
        components: [
          { name: "coverageAgent", type: "address", internalType: "address" },
          { name: "minRate", type: "uint16", internalType: "uint16" },
          { name: "maxDuration", type: "uint256", internalType: "uint256" },
          { name: "expiryTimestamp", type: "uint256", internalType: "uint256" },
          { name: "asset", type: "address", internalType: "address" },
          { name: "refundable", type: "uint8", internalType: "enum Refundable" },
          { name: "slashCoordinator", type: "address", internalType: "address" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "positionMaxAmount",
    inputs: [{ name: "positionId", type: "uint256", internalType: "uint256" }],
    outputs: [{ name: "maxAmount", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "slashClaims",
    inputs: [
      { name: "claimIds", type: "uint256[]", internalType: "uint256[]" },
      { name: "amounts", type: "uint256[]", internalType: "uint256[]" },
    ],
    outputs: [{ name: "slashStatuses", type: "uint8[]", internalType: "enum CoverageClaimStatus[]" }],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "ClaimCompleted",
    inputs: [{ name: "claimId", type: "uint256", indexed: true, internalType: "uint256" }],
    anonymous: false,
  },
  {
    type: "event",
    name: "ClaimIssued",
    inputs: [
      { name: "positionId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "claimId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "amount", type: "uint256", indexed: false, internalType: "uint256" },
      { name: "duration", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "ClaimSlashPending",
    inputs: [
      { name: "claimId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "slashCoordinator", type: "address", indexed: false, internalType: "address" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "ClaimSlashed",
    inputs: [
      { name: "claimId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "amount", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "CoverageIssued",
    inputs: [
      { name: "positionId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "claimId", type: "uint256", indexed: true, internalType: "uint256" },
      { name: "amount", type: "uint256", indexed: false, internalType: "uint256" },
      { name: "duration", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Liquidated",
    inputs: [{ name: "claimId", type: "uint256", indexed: true, internalType: "uint256" }],
    anonymous: false,
  },
  {
    type: "event",
    name: "PositionClosed",
    inputs: [{ name: "positionId", type: "uint256", indexed: true, internalType: "uint256" }],
    anonymous: false,
  },
  {
    type: "event",
    name: "PositionCreated",
    inputs: [{ name: "positionId", type: "uint256", indexed: true, internalType: "uint256" }],
    anonymous: false,
  },
] as const

export const eigenServiceManagerAbi = [
  {
    type: "function",
    name: "captureRewards",
    inputs: [{ name: "claimId", type: "uint256", internalType: "uint256" }],
    outputs: [
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "duration", type: "uint32", internalType: "uint32" },
      { name: "distributionStartTime", type: "uint32", internalType: "uint32" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "coverageAllocated",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "strategy", type: "address", internalType: "address" },
      { name: "coverageAgent", type: "address", internalType: "address" },
    ],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "eigenAddresses",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct EigenAddresses",
        components: [
          { name: "allocationManager", type: "address", internalType: "address" },
          { name: "delegationManager", type: "address", internalType: "address" },
          { name: "strategyManager", type: "address", internalType: "address" },
          { name: "rewardsCoordinator", type: "address", internalType: "address" },
          { name: "permissionController", type: "address", internalType: "address" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "ensureAllocations",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "coverageAgent", type: "address", internalType: "address" },
      { name: "strategy", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getAllocationedStrategies",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "coverageAgent", type: "address", internalType: "address" },
    ],
    outputs: [{ name: "", type: "address[]", internalType: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getOperatorSetId",
    inputs: [{ name: "coverageAgent", type: "address", internalType: "address" }],
    outputs: [{ name: "operatorSetId", type: "uint32", internalType: "uint32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isStrategyWhitelisted",
    inputs: [{ name: "strategy", type: "address", internalType: "address" }],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "registerOperator",
    inputs: [
      { name: "_operator", type: "address", internalType: "address" },
      { name: "_avs", type: "address", internalType: "address" },
      { name: "_operatorSetIds", type: "uint32[]", internalType: "uint32[]" },
      { name: "_data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setStrategyWhitelist",
    inputs: [
      { name: "strategyAddress", type: "address", internalType: "address" },
      { name: "whitelisted", type: "bool", internalType: "bool" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "slashOperator",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "strategy", type: "address", internalType: "address" },
      { name: "coverageAgent", type: "address", internalType: "address" },
      { name: "amount", type: "uint256", internalType: "uint256" },
    ],
    outputs: [{ name: "tokensReceived", type: "uint256", internalType: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "submitOperatorReward",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "strategy", type: "address", internalType: "contract IStrategy" },
      { name: "token", type: "address", internalType: "contract IERC20" },
      { name: "amount", type: "uint256", internalType: "uint256" },
      { name: "startTimestamp", type: "uint32", internalType: "uint32" },
      { name: "duration", type: "uint32", internalType: "uint32" },
      { name: "description", type: "string", internalType: "string" },
    ],
    outputs: [
      { name: "resolvedDistributionStartTime", type: "uint32", internalType: "uint32" },
      { name: "resolvedDuration", type: "uint32", internalType: "uint32" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "updateAVSMetadataURI",
    inputs: [{ name: "metadataURI", type: "string", internalType: "string" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const

// Get ABI for contract type
export function getAbiForContractType(type: string) {
  switch (type) {
    case "CoverageAgent":
      return coverageAgentAbi
    case "CoverageProvider":
      return coverageProviderAbi
    case "EigenServiceManager":
      return eigenServiceManagerAbi
    default:
      return []
  }
}
