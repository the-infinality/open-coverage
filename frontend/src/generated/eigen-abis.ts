//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// EigenLayer Contract ABIs
// These ABIs are for interacting with EigenLayer contracts directly
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IPermissionController
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iPermissionControllerAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'admin', internalType: 'address', type: 'address' },
    ],
    name: 'addPendingAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'admin', internalType: 'address', type: 'address' },
    ],
    name: 'removePendingAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'acceptAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'admin', internalType: 'address', type: 'address' },
    ],
    name: 'removeAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'caller', internalType: 'address', type: 'address' },
    ],
    name: 'isAdmin',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
      { name: 'pendingAdmin', internalType: 'address', type: 'address' },
    ],
    name: 'isPendingAdmin',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'getAdmins',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'getPendingAdmins',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'account', internalType: 'address', type: 'address', indexed: true },
      { name: 'admin', internalType: 'address', type: 'address', indexed: false },
    ],
    name: 'PendingAdminAdded',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'account', internalType: 'address', type: 'address', indexed: true },
      { name: 'admin', internalType: 'address', type: 'address', indexed: false },
    ],
    name: 'PendingAdminRemoved',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'account', internalType: 'address', type: 'address', indexed: true },
      { name: 'admin', internalType: 'address', type: 'address', indexed: false },
    ],
    name: 'AdminSet',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'account', internalType: 'address', type: 'address', indexed: true },
      { name: 'admin', internalType: 'address', type: 'address', indexed: false },
    ],
    name: 'AdminRemoved',
  },
  { type: 'error', inputs: [], name: 'NotAdmin' },
  { type: 'error', inputs: [], name: 'AdminNotSet' },
  { type: 'error', inputs: [], name: 'AdminAlreadySet' },
  { type: 'error', inputs: [], name: 'AdminNotPending' },
  { type: 'error', inputs: [], name: 'AdminAlreadyPending' },
  { type: 'error', inputs: [], name: 'CannotHaveZeroAdmins' },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IAllocationManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iAllocationManagerAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
    ],
    name: 'getAllocatedSets',
    outputs: [
      {
        name: '',
        internalType: 'struct OperatorSet[]',
        type: 'tuple[]',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      {
        name: 'operatorSet',
        internalType: 'struct OperatorSet',
        type: 'tuple',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    name: 'getAllocatedStrategies',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      {
        name: 'operatorSet',
        internalType: 'struct OperatorSet',
        type: 'tuple',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'getAllocation',
    outputs: [
      {
        name: '',
        internalType: 'struct Allocation',
        type: 'tuple',
        components: [
          { name: 'currentMagnitude', internalType: 'uint64', type: 'uint64' },
          { name: 'pendingDiff', internalType: 'int128', type: 'int128' },
          { name: 'effectBlock', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'getMaxMagnitude',
    outputs: [{ name: '', internalType: 'uint64', type: 'uint64' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategies', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'getMaxMagnitudes',
    outputs: [{ name: '', internalType: 'uint64[]', type: 'uint64[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'getEncumberedMagnitude',
    outputs: [{ name: '', internalType: 'uint64', type: 'uint64' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'getAllocatableMagnitude',
    outputs: [{ name: '', internalType: 'uint64', type: 'uint64' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
    ],
    name: 'getRegisteredSets',
    outputs: [
      {
        name: '',
        internalType: 'struct OperatorSet[]',
        type: 'tuple[]',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      {
        name: 'operatorSet',
        internalType: 'struct OperatorSet',
        type: 'tuple',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    name: 'isMemberOfOperatorSet',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'operatorSet',
        internalType: 'struct OperatorSet',
        type: 'tuple',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    name: 'getStrategiesInOperatorSet',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
    ],
    name: 'getAllocationDelay',
    outputs: [
      { name: 'isSet', internalType: 'bool', type: 'bool' },
      { name: 'delay', internalType: 'uint32', type: 'uint32' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'getStrategyAllocations',
    outputs: [
      {
        name: '',
        internalType: 'struct OperatorSet[]',
        type: 'tuple[]',
        components: [
          { name: 'avs', internalType: 'address', type: 'address' },
          { name: 'id', internalType: 'uint32', type: 'uint32' },
        ],
      },
      {
        name: '',
        internalType: 'struct Allocation[]',
        type: 'tuple[]',
        components: [
          { name: 'currentMagnitude', internalType: 'uint64', type: 'uint64' },
          { name: 'pendingDiff', internalType: 'int128', type: 'int128' },
          { name: 'effectBlock', internalType: 'uint32', type: 'uint32' },
        ],
      },
    ],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IDelegationManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iDelegationManagerAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
    ],
    name: 'isOperator',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'isDelegated',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'delegatedTo',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'approverSignatureAndExpiry', internalType: 'tuple', type: 'tuple', components: [
        { name: 'signature', internalType: 'bytes', type: 'bytes' },
        { name: 'expiry', internalType: 'uint256', type: 'uint256' },
      ]},
      { name: 'approverSalt', internalType: 'bytes32', type: 'bytes32' },
    ],
    name: 'delegateTo',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'undelegate',
    outputs: [{ name: '', internalType: 'bytes32[]', type: 'bytes32[]' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'operatorShares',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'getDepositedShares',
    outputs: [
      { name: '', internalType: 'address[]', type: 'address[]' },
      { name: '', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address', indexed: true },
      { name: 'operator', internalType: 'address', type: 'address', indexed: true },
    ],
    name: 'StakerDelegated',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address', indexed: true },
      { name: 'operator', internalType: 'address', type: 'address', indexed: true },
    ],
    name: 'StakerUndelegated',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IStrategyManager
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iStrategyManagerAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'strategy', internalType: 'address', type: 'address' },
      { name: 'token', internalType: 'address', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'depositIntoStrategy',
    outputs: [{ name: 'shares', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'getDeposits',
    outputs: [
      { name: '', internalType: 'address[]', type: 'address[]' },
      { name: '', internalType: 'uint256[]', type: 'uint256[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'getStakerStrategyList',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address' },
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'stakerDepositShares',
    outputs: [{ name: 'shares', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'strategy', internalType: 'address', type: 'address' },
    ],
    name: 'strategyIsWhitelistedForDeposit',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'staker', internalType: 'address', type: 'address', indexed: false },
      { name: 'strategy', internalType: 'address', type: 'address', indexed: false },
      { name: 'shares', internalType: 'uint256', type: 'uint256', indexed: false },
    ],
    name: 'Deposit',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IStrategy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iStrategyAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'underlyingToken',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalShares',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'shares', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'sharesToUnderlyingView',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountUnderlying', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'underlyingToSharesView',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IERC20
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const ierc20Abi = [
  {
    type: 'function',
    inputs: [],
    name: 'name',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'symbol',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'decimals',
    outputs: [{ name: '', internalType: 'uint8', type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'balanceOf',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'owner', internalType: 'address', type: 'address' },
      { name: 'spender', internalType: 'address', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'spender', internalType: 'address', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'to', internalType: 'address', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'transfer',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'from', internalType: 'address', type: 'address' },
      { name: 'to', internalType: 'address', type: 'address' },
      { name: 'amount', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'transferFrom',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'owner', internalType: 'address', type: 'address', indexed: true },
      { name: 'spender', internalType: 'address', type: 'address', indexed: true },
      { name: 'value', internalType: 'uint256', type: 'uint256', indexed: false },
    ],
    name: 'Approval',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'from', internalType: 'address', type: 'address', indexed: true },
      { name: 'to', internalType: 'address', type: 'address', indexed: true },
      { name: 'value', internalType: 'uint256', type: 'uint256', indexed: false },
    ],
    name: 'Transfer',
  },
] as const
