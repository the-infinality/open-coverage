//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// EigenOperatorProxy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const eigenOperatorProxyAbi = [
  {
    type: 'constructor',
    inputs: [
      {
        name: 'eigenAddresses_',
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
      { name: 'handler_', internalType: 'address', type: 'address' },
      { name: 'operatorMetadata_', internalType: 'string', type: 'string' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      {
        name: '_strategyAddresses',
        internalType: 'address[]',
        type: 'address[]',
      },
      { name: '_magnitudes', internalType: 'uint64[]', type: 'uint64[]' },
    ],
    name: 'allocate',
    outputs: [],
    stateMutability: 'nonpayable',
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
    inputs: [],
    name: 'handler',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      { name: 'rewardsSplit_', internalType: 'uint16', type: 'uint16' },
    ],
    name: 'registerCoverageAgent',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      { name: 'rewardsSplit_', internalType: 'uint16', type: 'uint16' },
    ],
    name: 'setRewardsSplit',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '_metadataUri', internalType: 'string', type: 'string' }],
    name: 'updateOperatorMetadataURI',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  { type: 'error', inputs: [], name: 'AlreadyAllocated' },
  { type: 'error', inputs: [], name: 'AlreadyRegistered' },
  {
    type: 'error',
    inputs: [{ name: 'rewardsSplit', internalType: 'uint16', type: 'uint16' }],
    name: 'InvalidRewardsSplit',
  },
  { type: 'error', inputs: [], name: 'NotOperator' },
  {
    type: 'error',
    inputs: [
      { name: 'operator', internalType: 'address', type: 'address' },
      { name: 'handler', internalType: 'address', type: 'address' },
    ],
    name: 'NotOperatorAuthorized',
  },
  { type: 'error', inputs: [], name: 'NotRestaker' },
  { type: 'error', inputs: [], name: 'NotServiceManager' },
  {
    type: 'error',
    inputs: [{ name: 'strategy', internalType: 'address', type: 'address' }],
    name: 'StrategyNotWhitelisted',
  },
  { type: 'error', inputs: [], name: 'ZeroAddress' },
] as const

export const eigenOperatorProxyBytecode = '0x608060405234801561000f575f5ffd5b506040516121643803806121648339818101604052810190610031919061063a565b825f5f820151815f015f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506020820151816001015f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506040820151816002015f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506060820151816003015f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055506080820151816004015f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055509050508160055f6101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505f6001015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16632aa6d8885f5f846040518463ffffffff1660e01b815260040161023293929190610758565b5f604051808303815f87803b158015610249575f5ffd5b505af115801561025b573d5f5f3e3d5ffd5b505050505f6004015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663eb5a4e8730846040518363ffffffff1660e01b81526004016102bd929190610794565b5f604051808303815f87803b1580156102d4575f5ffd5b505af11580156102e6573d5f5f3e3d5ffd5b505050505f6004015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663eb5a4e8730306040518363ffffffff1660e01b8152600401610348929190610794565b5f604051808303815f87803b15801561035f575f5ffd5b505af1158015610371573d5f5f3e3d5ffd5b505050505f6004015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663628806ef306040518263ffffffff1660e01b81526004016103d191906107bb565b5f604051808303815f87803b1580156103e8575f5ffd5b505af11580156103fa573d5f5f3e3d5ffd5b505050505050506107d4565b5f604051905090565b5f5ffd5b5f5ffd5b5f5ffd5b5f601f19601f8301169050919050565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b6104618261041b565b810181811067ffffffffffffffff821117156104805761047f61042b565b5b80604052505050565b5f610492610406565b905061049e8282610458565b919050565b5f73ffffffffffffffffffffffffffffffffffffffff82169050919050565b5f6104cc826104a3565b9050919050565b6104dc816104c2565b81146104e6575f5ffd5b50565b5f815190506104f7816104d3565b92915050565b5f60a0828403121561051257610511610417565b5b61051c60a0610489565b90505f61052b848285016104e9565b5f83015250602061053e848285016104e9565b6020830152506040610552848285016104e9565b6040830152506060610566848285016104e9565b606083015250608061057a848285016104e9565b60808301525092915050565b5f5ffd5b5f5ffd5b5f67ffffffffffffffff8211156105a8576105a761042b565b5b6105b18261041b565b9050602081019050919050565b8281835e5f83830152505050565b5f6105de6105d98461058e565b610489565b9050828152602081018484840111156105fa576105f961058a565b5b6106058482856105be565b509392505050565b5f82601f83011261062157610620610586565b5b81516106318482602086016105cc565b91505092915050565b5f5f5f60e084860312156106515761065061040f565b5b5f61065e868287016104fd565b93505060a061066f868287016104e9565b92505060c084015167ffffffffffffffff8111156106905761068f610413565b5b61069c8682870161060d565b9150509250925092565b6106af816104c2565b82525050565b5f819050919050565b5f63ffffffff82169050919050565b5f819050919050565b5f6106f06106eb6106e6846106b5565b6106cd565b6106be565b9050919050565b610700816106d6565b82525050565b5f81519050919050565b5f82825260208201905092915050565b5f61072a82610706565b6107348185610710565b93506107448185602086016105be565b61074d8161041b565b840191505092915050565b5f60608201905061076b5f8301866106a6565b61077860208301856106f7565b818103604083015261078a8184610720565b9050949350505050565b5f6040820190506107a75f8301856106a6565b6107b460208301846106a6565b9392505050565b5f6020820190506107ce5f8301846106a6565b92915050565b611983806107e15f395ff3fe608060405234801561000f575f5ffd5b5060043610610070575f3560e01c806399be81c81161004e57806399be81c8146100ca578063c80916d4146100e6578063d9ec48631461010457610070565b80636549991f1461007457806372e8e3e614610090578063754061a3146100ac575b5f5ffd5b61008e60048036038101906100899190610ed3565b610120565b005b6100aa60048036038101906100a59190610fd9565b610138565b005b6100b461053f565b6040516100c191906110f1565b60405180910390f35b6100e460048036038101906100df919061115f565b610700565b005b6100ee610817565b6040516100fb91906111b9565b60405180910390f35b61011e60048036038101906101199190610ed3565b61083f565b005b610128610b24565b610133838383610bb9565b505050565b610140610b24565b5f8673ffffffffffffffffffffffffffffffffffffffff1663110416cb876040518263ffffffff1660e01b815260040161017a91906111b9565b602060405180830381865afa158015610195573d5f5f3e3d5ffd5b505050506040513d601f19601f820116820180604052508101906101b9919061120b565b90505f8585905067ffffffffffffffff8111156101d9576101d8611236565b5b6040519080825280602002602001820160405280156102075781602001602082028036833780820191505090505b5090505f5f90505b868690508110156103a3578873ffffffffffffffffffffffffffffffffffffffff1663999ba27c88888481811061024957610248611263565b5b905060200201602081019061025e9190611290565b6040518263ffffffff1660e01b815260040161027a91906111b9565b602060405180830381865afa158015610295573d5f5f3e3d5ffd5b505050506040513d601f19601f820116820180604052508101906102b991906112f0565b610321578686828181106102d0576102cf611263565b5b90506020020160208101906102e59190611290565b6040517f4f6f6ef700000000000000000000000000000000000000000000000000000000815260040161031891906111b9565b60405180910390fd5b86868281811061033457610333611263565b5b90506020020160208101906103499190611290565b82828151811061035c5761035b611263565b5b602002602001019073ffffffffffffffffffffffffffffffffffffffff16908173ffffffffffffffffffffffffffffffffffffffff1681525050808060010191505061020f565b505f60405180604001604052808a73ffffffffffffffffffffffffffffffffffffffff1681526020018463ffffffff1681525090505f600167ffffffffffffffff8111156103f4576103f3611236565b5b60405190808252806020026020018201604052801561042d57816020015b61041a610d47565b8152602001906001900390816104125790505b50905060405180606001604052808381526020018481526020018787808060200260200160405190810160405280939291908181526020018383602002808284375f81840152601f19601f82011690508083019250505050505050815250815f8151811061049e5761049d611263565b5b60200260200101819052505f5f015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663952899ee30836040518363ffffffff1660e01b8152600401610506929190611633565b5f604051808303815f87803b15801561051d575f5ffd5b505af115801561052f573d5f5f3e3d5ffd5b5050505050505050505050505050565b610547610d6e565b5f6040518060a00160405290815f82015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001600182015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001600282015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001600382015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001600482015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681525050905090565b60055f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614610786576040517f7c214f0400000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f6001015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff166378296ec53084846040518463ffffffff1660e01b81526004016107e6939291906116bb565b5f604051808303815f87803b1580156107fd575f5ffd5b505af115801561080f573d5f5f3e3d5ffd5b505050505050565b5f60055f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff16905090565b610847610b24565b5f8373ffffffffffffffffffffffffffffffffffffffff1663110416cb846040518263ffffffff1660e01b815260040161088191906111b9565b602060405180830381865afa15801561089c573d5f5f3e3d5ffd5b505050506040513d601f19601f820116820180604052508101906108c0919061120b565b90505f60405180604001604052808673ffffffffffffffffffffffffffffffffffffffff1681526020018363ffffffff1681525090505f5f015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663670d3ba230836040518363ffffffff1660e01b8152600401610953929190611718565b602060405180830381865afa15801561096e573d5f5f3e3d5ffd5b505050506040513d601f19601f8201168201806040525081019061099291906112f0565b156109c9576040517f3a81d6fc00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f600167ffffffffffffffff8111156109e5576109e4611236565b5b604051908082528060200260200182016040528015610a135781602001602082028036833780820191505090505b50905082815f81518110610a2a57610a29611263565b5b602002602001019063ffffffff16908163ffffffff16815250505f60405180606001604052808873ffffffffffffffffffffffffffffffffffffffff16815260200183815260200160405180602001604052805f81525081525090505f5f015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663adc2e3d930836040518363ffffffff1660e01b8152600401610ae392919061189b565b5f604051808303815f87803b158015610afa575f5ffd5b505af1158015610b0c573d5f5f3e3d5ffd5b50505050610b1b878787610bb9565b50505050505050565b60055f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff1614610bb75730336040517fc6c577fd000000000000000000000000000000000000000000000000000000008152600401610bae9291906118c9565b60405180910390fd5b565b6127108161ffff161115610c0457806040517fe1a8a46e000000000000000000000000000000000000000000000000000000008152600401610bfb91906118ff565b60405180910390fd5b5f8373ffffffffffffffffffffffffffffffffffffffff1663110416cb846040518263ffffffff1660e01b8152600401610c3e91906111b9565b602060405180830381865afa158015610c59573d5f5f3e3d5ffd5b505050506040513d601f19601f82011682018060405250810190610c7d919061120b565b90505f60405180604001604052808673ffffffffffffffffffffffffffffffffffffffff1681526020018363ffffffff1681525090505f6003015f9054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663f74e8eac3083866040518463ffffffff1660e01b8152600401610d1393929190611918565b5f604051808303815f87803b158015610d2a575f5ffd5b505af1158015610d3c573d5f5f3e3d5ffd5b505050505050505050565b6040518060600160405280610d5a610e06565b815260200160608152602001606081525090565b6040518060a001604052805f73ffffffffffffffffffffffffffffffffffffffff1681526020015f73ffffffffffffffffffffffffffffffffffffffff1681526020015f73ffffffffffffffffffffffffffffffffffffffff1681526020015f73ffffffffffffffffffffffffffffffffffffffff1681526020015f73ffffffffffffffffffffffffffffffffffffffff1681525090565b60405180604001604052805f73ffffffffffffffffffffffffffffffffffffffff1681526020015f63ffffffff1681525090565b5f5ffd5b5f5ffd5b5f73ffffffffffffffffffffffffffffffffffffffff82169050919050565b5f610e6b82610e42565b9050919050565b610e7b81610e61565b8114610e85575f5ffd5b50565b5f81359050610e9681610e72565b92915050565b5f61ffff82169050919050565b610eb281610e9c565b8114610ebc575f5ffd5b50565b5f81359050610ecd81610ea9565b92915050565b5f5f5f60608486031215610eea57610ee9610e3a565b5b5f610ef786828701610e88565b9350506020610f0886828701610e88565b9250506040610f1986828701610ebf565b9150509250925092565b5f5ffd5b5f5ffd5b5f5ffd5b5f5f83601f840112610f4457610f43610f23565b5b8235905067ffffffffffffffff811115610f6157610f60610f27565b5b602083019150836020820283011115610f7d57610f7c610f2b565b5b9250929050565b5f5f83601f840112610f9957610f98610f23565b5b8235905067ffffffffffffffff811115610fb657610fb5610f27565b5b602083019150836020820283011115610fd257610fd1610f2b565b5b9250929050565b5f5f5f5f5f5f60808789031215610ff357610ff2610e3a565b5b5f61100089828a01610e88565b965050602061101189828a01610e88565b955050604087013567ffffffffffffffff81111561103257611031610e3e565b5b61103e89828a01610f2f565b9450945050606087013567ffffffffffffffff81111561106157611060610e3e565b5b61106d89828a01610f84565b92509250509295509295509295565b61108581610e61565b82525050565b60a082015f82015161109f5f85018261107c565b5060208201516110b2602085018261107c565b5060408201516110c5604085018261107c565b5060608201516110d8606085018261107c565b5060808201516110eb608085018261107c565b50505050565b5f60a0820190506111045f83018461108b565b92915050565b5f5f83601f84011261111f5761111e610f23565b5b8235905067ffffffffffffffff81111561113c5761113b610f27565b5b60208301915083600182028301111561115857611157610f2b565b5b9250929050565b5f5f6020838503121561117557611174610e3a565b5b5f83013567ffffffffffffffff81111561119257611191610e3e565b5b61119e8582860161110a565b92509250509250929050565b6111b381610e61565b82525050565b5f6020820190506111cc5f8301846111aa565b92915050565b5f63ffffffff82169050919050565b6111ea816111d2565b81146111f4575f5ffd5b50565b5f81519050611205816111e1565b92915050565b5f602082840312156112205761121f610e3a565b5b5f61122d848285016111f7565b91505092915050565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b7f4e487b71000000000000000000000000000000000000000000000000000000005f52603260045260245ffd5b5f602082840312156112a5576112a4610e3a565b5b5f6112b284828501610e88565b91505092915050565b5f8115159050919050565b6112cf816112bb565b81146112d9575f5ffd5b50565b5f815190506112ea816112c6565b92915050565b5f6020828403121561130557611304610e3a565b5b5f611312848285016112dc565b91505092915050565b5f81519050919050565b5f82825260208201905092915050565b5f819050602082019050919050565b61134d816111d2565b82525050565b604082015f8201516113675f85018261107c565b50602082015161137a6020850182611344565b50505050565b5f81519050919050565b5f82825260208201905092915050565b5f819050602082019050919050565b5f819050919050565b5f6113cc6113c76113c284610e42565b6113a9565b610e42565b9050919050565b5f6113dd826113b2565b9050919050565b5f6113ee826113d3565b9050919050565b6113fe816113e4565b82525050565b5f61140f83836113f5565b60208301905092915050565b5f602082019050919050565b5f61143182611380565b61143b818561138a565b93506114468361139a565b805f5b8381101561147657815161145d8882611404565b97506114688361141b565b925050600181019050611449565b5085935050505092915050565b5f81519050919050565b5f82825260208201905092915050565b5f819050602082019050919050565b5f67ffffffffffffffff82169050919050565b6114c8816114ac565b82525050565b5f6114d983836114bf565b60208301905092915050565b5f602082019050919050565b5f6114fb82611483565b611505818561148d565b93506115108361149d565b805f5b8381101561154057815161152788826114ce565b9750611532836114e5565b925050600181019050611513565b5085935050505092915050565b5f608083015f8301516115625f860182611353565b506020830151848203604086015261157a8282611427565b9150506040830151848203606086015261159482826114f1565b9150508091505092915050565b5f6115ac838361154d565b905092915050565b5f602082019050919050565b5f6115ca8261131b565b6115d48185611325565b9350836020820285016115e685611335565b805f5b85811015611621578484038952815161160285826115a1565b945061160d836115b4565b925060208a019950506001810190506115e9565b50829750879550505050505092915050565b5f6040820190506116465f8301856111aa565b818103602083015261165881846115c0565b90509392505050565b5f82825260208201905092915050565b828183375f83830152505050565b5f601f19601f8301169050919050565b5f61169a8385611661565b93506116a7838584611671565b6116b08361167f565b840190509392505050565b5f6040820190506116ce5f8301866111aa565b81810360208301526116e181848661168f565b9050949350505050565b604082015f8201516116ff5f85018261107c565b5060208201516117126020850182611344565b50505050565b5f60608201905061172b5f8301856111aa565b61173860208301846116eb565b9392505050565b5f81519050919050565b5f82825260208201905092915050565b5f819050602082019050919050565b5f6117738383611344565b60208301905092915050565b5f602082019050919050565b5f6117958261173f565b61179f8185611749565b93506117aa83611759565b805f5b838110156117da5781516117c18882611768565b97506117cc8361177f565b9250506001810190506117ad565b5085935050505092915050565b5f81519050919050565b5f82825260208201905092915050565b8281835e5f83830152505050565b5f611819826117e7565b61182381856117f1565b9350611833818560208601611801565b61183c8161167f565b840191505092915050565b5f606083015f83015161185c5f86018261107c565b5060208301518482036020860152611874828261178b565b9150506040830151848203604086015261188e828261180f565b9150508091505092915050565b5f6040820190506118ae5f8301856111aa565b81810360208301526118c08184611847565b90509392505050565b5f6040820190506118dc5f8301856111aa565b6118e960208301846111aa565b9392505050565b6118f981610e9c565b82525050565b5f6020820190506119125f8301846118f0565b92915050565b5f60808201905061192b5f8301866111aa565b61193860208301856116eb565b61194560608301846118f0565b94935050505056fea2646970667358221220f14fc71ddcc0bf11e6ce5b09d585afa6801c8daf03eaaaf4f8fcf2a97a3ca2dc64736f6c63430008210033' as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IAssetPriceOracleAndSwapper
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iAssetPriceOracleAndSwapperAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'assetPair',
    outputs: [
      {
        name: '',
        internalType: 'struct AssetPair',
        type: 'tuple',
        components: [
          { name: 'assetA', internalType: 'address', type: 'address' },
          { name: 'assetB', internalType: 'address', type: 'address' },
          { name: 'swapEngine', internalType: 'address', type: 'address' },
          { name: 'poolInfo', internalType: 'bytes', type: 'bytes' },
          {
            name: 'priceStrategy',
            internalType: 'enum PriceStrategy',
            type: 'uint8',
          },
          { name: 'swapperAccuracy', internalType: 'uint16', type: 'uint16' },
          { name: 'priceOracle', internalType: 'address', type: 'address' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountIn', internalType: 'uint256', type: 'uint256' },
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'getQuote',
    outputs: [
      { name: 'quote', internalType: 'uint256', type: 'uint256' },
      { name: 'verified', internalType: 'bool', type: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: '_assetPair',
        internalType: 'struct AssetPair',
        type: 'tuple',
        components: [
          { name: 'assetA', internalType: 'address', type: 'address' },
          { name: 'assetB', internalType: 'address', type: 'address' },
          { name: 'swapEngine', internalType: 'address', type: 'address' },
          { name: 'poolInfo', internalType: 'bytes', type: 'bytes' },
          {
            name: 'priceStrategy',
            internalType: 'enum PriceStrategy',
            type: 'uint8',
          },
          { name: 'swapperAccuracy', internalType: 'uint16', type: 'uint16' },
          { name: 'priceOracle', internalType: 'address', type: 'address' },
        ],
      },
    ],
    name: 'register',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'swapSlippage_', internalType: 'uint16', type: 'uint16' }],
    name: 'setSwapSlippage',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountIn', internalType: 'uint256', type: 'uint256' },
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'swapForInput',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountIn', internalType: 'uint256', type: 'uint256' },
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'swapForInputQuote',
    outputs: [
      { name: 'minAmountOut', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountOut', internalType: 'uint256', type: 'uint256' },
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'swapForOutput',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'amountOut', internalType: 'uint256', type: 'uint256' },
      { name: 'assetA', internalType: 'address', type: 'address' },
      { name: 'assetB', internalType: 'address', type: 'address' },
    ],
    name: 'swapForOutputQuote',
    outputs: [
      { name: 'maxAmountIn', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'swapSlippage',
    outputs: [{ name: '', internalType: 'uint16', type: 'uint16' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'assetA',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'assetB',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'AssetPairRegistered',
  },
  { type: 'error', inputs: [], name: 'AssetPairNotRegistered' },
  { type: 'error', inputs: [], name: 'InvalidAssetPair' },
  { type: 'error', inputs: [], name: 'InvalidPoolInfo' },
  { type: 'error', inputs: [], name: 'InvalidSwapSlippage' },
  { type: 'error', inputs: [], name: 'PriceMismatch' },
  { type: 'error', inputs: [], name: 'PriceOracleRequired' },
  { type: 'error', inputs: [], name: 'SwapFailed' },
] as const

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
// IDiamondOwner
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iDiamondOwnerAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ name: 'owner_', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', internalType: 'address', type: 'address' }],
    name: 'setOwner',
    outputs: [],
    stateMutability: 'nonpayable',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IEigenOperatorProxy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iEigenOperatorProxyAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      {
        name: '_strategyAddresses',
        internalType: 'address[]',
        type: 'address[]',
      },
      { name: '_magnitudes', internalType: 'uint64[]', type: 'uint64[]' },
    ],
    name: 'allocate',
    outputs: [],
    stateMutability: 'nonpayable',
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
    inputs: [],
    name: 'handler',
    outputs: [{ name: 'handler', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      { name: 'rewardsSplit_', internalType: 'uint16', type: 'uint16' },
    ],
    name: 'registerCoverageAgent',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'serviceManager_', internalType: 'address', type: 'address' },
      { name: 'coverageAgent_', internalType: 'address', type: 'address' },
      { name: 'rewardsSplit_', internalType: 'uint16', type: 'uint16' },
    ],
    name: 'setRewardsSplit',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '_metadataUri', internalType: 'string', type: 'string' }],
    name: 'updateOperatorMetadataURI',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  { type: 'error', inputs: [], name: 'AlreadyAllocated' },
  { type: 'error', inputs: [], name: 'AlreadyRegistered' },
  {
    type: 'error',
    inputs: [{ name: 'rewardsSplit', internalType: 'uint16', type: 'uint16' }],
    name: 'InvalidRewardsSplit',
  },
  { type: 'error', inputs: [], name: 'NotOperator' },
  { type: 'error', inputs: [], name: 'NotRestaker' },
  { type: 'error', inputs: [], name: 'NotServiceManager' },
  { type: 'error', inputs: [], name: 'ZeroAddress' },
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
