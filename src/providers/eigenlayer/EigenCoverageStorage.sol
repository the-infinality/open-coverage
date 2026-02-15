// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {EigenAddresses} from "./Types.sol";
import {CoveragePosition, CoverageClaim} from "../../interfaces/ICoverageProvider.sol";

/// @notice Data structure tracking an operator's coverage allocations
struct OperatorData {
    /// @notice The amount of coverage issued by an operator per strategy
    /// @dev The key is the strategy providing coverage
    /// @dev The keys of the EnumerableMap is the coverage agent being covered.
    mapping(address => EnumerableMap.AddressToUintMap) coverageStrategies;

    /// @notice The coverage liquidty threshold for an operator before claims stop being issued
    uint16 coverageThreshold;
}

/// @notice Data structure for tracking reward distribution per claim
struct ClaimRewardDistribution {
    uint256 amount;
    uint32 lastDistributedTimestamp;
}

/// @title EigenCoverageStorage
/// @author p-dealwis, Infinality
/// @notice Storage contract for EigenCoverageDiamond containing all app-specific state variables
/// @dev This contract should be inherited by EigenCoverageDiamond and all facets to maintain storage layout.
///      Note: Diamond-specific storage (facets, selectors, owner) is managed separately via LibDiamond
///      at a fixed storage slot, so it won't collide with this app-specific storage.
///
///      Initialization (Slither reports the following as uninitialized because it does not model diamond delegatecall storage):
///      - _eigenAddresses: set in EigenCoverageDiamond constructor (DiamondArgs.eigenAddresses)
///      - assetToStrategy: set per-asset in EigenServiceManagerFacet.setStrategyWhitelist (owner-only)
///      - coverageAgentToOperatorSetId: set per-agent in EigenCoverageProviderFacet.onIsRegistered when agent registers
abstract contract EigenCoverageStorage {
    /// @notice Eigen protocol contract addresses (initialized in EigenCoverageDiamond constructor)
    EigenAddresses internal _eigenAddresses;

    /// @notice Counter for operator set IDs, incremented when new coverage agents register
    uint32 internal _operatorSetCount;

    /// @notice Array of all coverage positions created
    CoveragePosition[] public positions;

    /// @notice Array of all coverage claims
    CoverageClaim[] public claims;

    /// @notice Mapping from coverage agent address to their operator set ID (written in EigenCoverageProviderFacet.onIsRegistered)
    mapping(address => uint32) public coverageAgentToOperatorSetId;

    /// @notice Mapping of whitelisted strategies (address => 1 if whitelisted)
    /// @dev Use EnumerableMap to allow enumeration of all whitelisted strategies
    EnumerableMap.AddressToUintMap internal _strategyWhitelist;

    /// @notice Mapping from asset address to strategy address (written in EigenServiceManagerFacet.setStrategyWhitelist)
    mapping(address => address) public assetToStrategy;

    /// @notice Mapping from operator address to their data
    mapping(address => OperatorData) public operators;

    /// @notice The amount of reward distributed to the operator for a given claim
    mapping(uint256 claimId => ClaimRewardDistribution) public claimRewardDistributions;

    /// @notice The amount of coverage agent assets to slash for a given claim
    mapping(uint256 claimId => uint256 amount) public claimSlashAmounts;

    /// @notice The liquidity threshold for an operator before their claims can be liquidated by another operator
    uint16 internal _liquidationThreshold = 9000;

    /// @dev Gap for future storage variables (following OpenZeppelin upgradeable pattern)
    uint256[50] private __gap;
}
