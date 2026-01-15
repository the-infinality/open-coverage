//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ICoverageAgent
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iCoverageAgentAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'asset',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'coordinator',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'coverageId', internalType: 'uint256', type: 'uint256' }],
    name: 'coverage',
    outputs: [
      {
        name: 'coverage',
        internalType: 'struct Coverage',
        type: 'tuple',
        components: [
          {
            name: 'claims',
            internalType: 'struct Claim[]',
            type: 'tuple[]',
            components: [
              {
                name: 'coverageProvider',
                internalType: 'address',
                type: 'address',
              },
              { name: 'claimId', internalType: 'uint256', type: 'uint256' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'coverageProvider', internalType: 'address', type: 'address' },
    ],
    name: 'isCoverageProviderRegistered',
    outputs: [{ name: 'isRegistered', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    name: 'onRegisterPosition',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'claimId', internalType: 'uint256', type: 'uint256' },
      { name: 'slashAmount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'onSlashCompleted',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'coverageProvider', internalType: 'address', type: 'address' },
    ],
    name: 'registerCoverageProvider',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'registeredCoverageProviders',
    outputs: [
      {
        name: 'coverageProviderAddresses',
        internalType: 'address[]',
        type: 'address[]',
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'coverageId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'CoverageClaimed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'coverageProvider',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'CoverageProviderRegistered',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'coverageProvider',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'positionId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'PositionRegistered',
  },
  {
    type: 'error',
    inputs: [{ name: 'coverageId', internalType: 'uint256', type: 'uint256' }],
    name: 'InvalidCoverage',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ICoverageProvider
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iCoverageProviderAbi = [
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'claim',
    outputs: [
      {
        name: 'claim',
        internalType: 'struct CoverageClaim',
        type: 'tuple',
        components: [
          { name: 'positionId', internalType: 'uint256', type: 'uint256' },
          { name: 'amount', internalType: 'uint256', type: 'uint256' },
          { name: 'duration', internalType: 'uint256', type: 'uint256' },
          { name: 'createdAt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'status',
            internalType: 'enum CoverageClaimStatus',
            type: 'uint8',
          },
          { name: 'reward', internalType: 'uint256', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'claimBacking',
    outputs: [{ name: 'backing', internalType: 'int256', type: 'int256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'positionId', internalType: 'uint256', type: 'uint256' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
      { name: 'duration', internalType: 'uint256', type: 'uint256' },
      { name: 'reward', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'claimCoverage',
    outputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'claimTotalSlashAmount',
    outputs: [
      { name: 'slashAmount', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    name: 'closePosition',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'completeClaims',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'completeSlash',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
      {
        name: 'data',
        internalType: 'struct CoveragePosition',
        type: 'tuple',
        components: [
          { name: 'coverageAgent', internalType: 'address', type: 'address' },
          { name: 'minRate', internalType: 'uint16', type: 'uint16' },
          { name: 'maxDuration', internalType: 'uint256', type: 'uint256' },
          { name: 'expiryTimestamp', internalType: 'uint256', type: 'uint256' },
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'refundable',
            internalType: 'enum Refundable',
            type: 'uint8',
          },
          {
            name: 'slashCoordinator',
            internalType: 'address',
            type: 'address',
          },
        ],
      },
      { name: 'additionalData', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'createPosition',
    outputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'liquidateClaim',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'onIsRegistered',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    name: 'position',
    outputs: [
      {
        name: 'position',
        internalType: 'struct CoveragePosition',
        type: 'tuple',
        components: [
          { name: 'coverageAgent', internalType: 'address', type: 'address' },
          { name: 'minRate', internalType: 'uint16', type: 'uint16' },
          { name: 'maxDuration', internalType: 'uint256', type: 'uint256' },
          { name: 'expiryTimestamp', internalType: 'uint256', type: 'uint256' },
          { name: 'asset', internalType: 'address', type: 'address' },
          {
            name: 'refundable',
            internalType: 'enum Refundable',
            type: 'uint8',
          },
          {
            name: 'slashCoordinator',
            internalType: 'address',
            type: 'address',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    name: 'positionMaxAmount',
    outputs: [{ name: 'maxAmount', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'claimIds', internalType: 'uint256[]', type: 'uint256[]' },
      { name: 'amounts', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    name: 'slashClaims',
    outputs: [
      {
        name: 'slashStatuses',
        internalType: 'enum CoverageClaimStatus[]',
        type: 'uint8[]',
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'ClaimCompleted',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'positionId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'duration',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'ClaimIssued',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'slashCoordinator',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'ClaimSlashPending',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'ClaimSlashed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'positionId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
      {
        name: 'amount',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
      {
        name: 'duration',
        internalType: 'uint256',
        type: 'uint256',
        indexed: false,
      },
    ],
    name: 'CoverageIssued',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'claimId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'Liquidated',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'positionId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'PositionClosed',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'positionId',
        internalType: 'uint256',
        type: 'uint256',
        indexed: true,
      },
    ],
    name: 'PositionCreated',
  },
  {
    type: 'error',
    inputs: [
      { name: 'maxDuration', internalType: 'uint256', type: 'uint256' },
      { name: 'duration', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'DurationExceedsMax',
  },
  {
    type: 'error',
    inputs: [{ name: 'deficit', internalType: 'uint256', type: 'uint256' }],
    name: 'InsufficientCoverageAvailable',
  },
  {
    type: 'error',
    inputs: [
      { name: 'minimumReward', internalType: 'uint256', type: 'uint256' },
      { name: 'reward', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'InsufficientReward',
  },
  { type: 'error', inputs: [], name: 'InvalidAmount' },
  {
    type: 'error',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'InvalidClaim',
  },
  {
    type: 'error',
    inputs: [{ name: 'minRate', internalType: 'uint16', type: 'uint16' }],
    name: 'MinRateInvalid',
  },
  {
    type: 'error',
    inputs: [
      { name: 'caller', internalType: 'address', type: 'address' },
      { name: 'required', internalType: 'address', type: 'address' },
    ],
    name: 'NotCoverageAgent',
  },
  {
    type: 'error',
    inputs: [{ name: 'positionId', internalType: 'uint256', type: 'uint256' }],
    name: 'PositionExpired',
  },
  { type: 'error', inputs: [], name: 'RewardTransferFailed' },
  {
    type: 'error',
    inputs: [
      { name: 'claimId', internalType: 'uint256', type: 'uint256' },
      { name: 'slash', internalType: 'uint256', type: 'uint256' },
      { name: 'claim', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'SlashAmountExceedsClaim',
  },
  {
    type: 'error',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'SlashFailed',
  },
  {
    type: 'error',
    inputs: [{ name: 'timestamp', internalType: 'uint256', type: 'uint256' }],
    name: 'TimestampInvalid',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IEigenServiceManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iEigenServiceManagerAbi = [
  {
    type: 'function',
    inputs: [{ name: 'claimId', internalType: 'uint256', type: 'uint256' }],
    name: 'captureRewards',
    outputs: [
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
      { name: 'duration', internalType: 'uint32', type: 'uint32' },
      { name: 'distributionStartTime', internalType: 'uint32', type: 'uint32' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
    ],
    name: 'coverageAllocated',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'eigenAddresses',
    outputs: [
      {
        name: '',
        internalType: 'struct EigenAddresses',
        type: 'tuple',
        components: [
          {
            name: 'allocationManager',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'delegationManager',
            internalType: 'address',
            type: 'address',
          },
          { name: 'strategyManager', internalType: 'address', type: 'address' },
          {
            name: 'rewardsCoordinator',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'permissionController',
            internalType: 'address',
            type: 'address',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'ensureAllocations',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
    ],
    name: 'getAllocationedStrategies',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
    ],
    name: 'getOperatorSetId',
    outputs: [
      { name: 'operatorSetId', internalType: 'uint32', type: 'uint32' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'strategy', internalType: 'address', type: 'address' }],
    name: 'isStrategyWhitelisted',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: '_operator', internalType: 'address', type: 'address' },
      { name: '_avs', internalType: 'address', type: 'address' },
      { name: '_operatorSetIds', internalType: 'uint32[]', type: 'uint32[]' },
      { name: '_data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'registerOperator',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'strategyAddress', internalType: 'address', type: 'address' },
      { name: 'whitelisted', internalType: 'bool', type: 'bool' },
    ],
    name: 'setStrategyWhitelist',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
      { name: 'coverageAgent', internalType: 'address', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'slashOperator',
    outputs: [
      { name: 'tokensReceived', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'contract IStrategy', type: 'address' },
      { name: 'token', internalType: 'contract IERC20', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
      { name: 'startTimestamp', internalType: 'uint32', type: 'uint32' },
      { name: 'duration', internalType: 'uint32', type: 'uint32' },
      { name: 'description', internalType: 'string', type: 'string' },
    ],
    name: 'submitOperatorReward',
    outputs: [
      {
        name: 'resolvedDistributionStartTime',
        internalType: 'uint32',
        type: 'uint32',
      },
      { name: 'resolvedDuration', internalType: 'uint32', type: 'uint32' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'metadataURI', internalType: 'string', type: 'string' }],
    name: 'updateAVSMetadataURI',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'error',
    inputs: [{ name: 'asset', internalType: 'address', type: 'address' }],
    name: 'StrategyAssetAlreadyRegistered',
  },
  {
    type: 'error',
    inputs: [{ name: 'strategy', internalType: 'address', type: 'address' }],
    name: 'StrategyNotWhitelisted',
  },
] as const
