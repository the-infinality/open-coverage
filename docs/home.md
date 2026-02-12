# Open Coverage

Open Coverage is a risk coverage standard focussed on simplifying the process of providing and purchasing risk coverage by making it more accessible via standardisation.

## How it works

There are two core concepts in Open Coverage:

1. **Coverage Providers** - These are the entities that provide risk coverage.
2. **Coverage Agents** - These are the entities that purchase risk coverage.

### Coverage Providers

Coverage Providers are the entities that provide risk coverage by allocating liquidity towards coverage. They allow Coverage Agents to purchase coverage by pricing in risk coverage for the specific assets they will use to cover the risk. A Coverage Provider accepts slashing responsibility in return for a fee that is paid to by the Coverage Agent.

#### How to become a Coverage Provider

You must have a vault or equivalent with capital allocated via staking to provide risk coverage before creating a contract that implements the Coverage Provider interface to enable creation of coverage positions, issuance of claims, distribution of rewards and slashing of coverage in the event of a claim being exercised by the Coverage Agent. The Coverage Providerinterface is unopinionated and therefore any sort of capital allocation mechanism may be used to provide risk coverage.

### Coverage Agents

Coverage Agents are the entities that purchase risk coverage. They are responsible for purchasing coverage from Coverage Providers in order to cover the risk of a certain opportunity. The Coverage Agent is essentially the conduit for a protocol that wants to specialise in a specific opportunity like DeFi vault protection, smart contract loss protection, asset price peg protection, etc.

#### How to become a Coverage Agent

Covearge Agents are responsible for purchasing the coverage and handling their claims process with care to ensure coverage can not be gamed by third parties. Therefore, while Coverage Agents needs to explicitly register against a Coverage Provider to purchase coverage, the Coverage Provider is not obliged to provide coverage to all Coverage Agent, especially if they are not comfortable with the risk profile of the Coverage Agent. It is imperitive that a Coverage Agent finds suitable allocators that are willing to provide coverage by building business relationships the providing adequete documentation to promote transparency and trust.

## Exisitng Coverage Providers

- [Eigenlayer](providers/eigenlayer.md)

## Auxiliary Contracts

### [AssetPriceOracleAndSwapper](mixins/asset-price-oracle-and-swapper.md)

### [Swapper Engines](swapper-engines/index.md)
