// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnumerableMap} from "@openzeppelin-v5/contracts/utils/structs/EnumerableMap.sol";
import {EigenAddresses} from "../Types.sol";
import {CoveragePosition} from "../../../interfaces/ICoverageProvider.sol";

struct CreatePositionAddtionalData {
    address operator;
    address strategy;
}

struct EigenCoveragePosition {
    CoveragePosition data;
    address operator;
    address strategy;
}

struct OperatorData {
    /// @notice The amount of coverage issued by an operator per strategy
    /// @dev The key is the strategy providing coverage
    /// @dev The keys of the EnumerableMap is the coverage agent being covered.
    mapping(address => EnumerableMap.AddressToUintMap) coverageStrategies;
    bool active;
}

/// @notice An interface for the Eigen coverage provider.
interface IEigenServiceManager {
    error StrategyAssetAlreadyRegistered(address asset);
    error StrategyNotWhitelisted(address strategy);

    function eigenAddresses() external view returns (EigenAddresses memory);

    /// @notice Registers an operator to the AVS, called by the Allocation Manager contract (access control set for the allocation manager).
    /// @param _operator The operator to register
    /// @param _avs The AVS to register the operator to
    /// @param _operatorSetIds The operator set ids to register the operator to
    /// @param _data Additional data
    function registerOperator(address _operator, address _avs, uint32[] calldata _operatorSetIds, bytes calldata _data)
        external;

    /// @notice Sets the whitelist status for a strategy
    /// @param strategyAddress The strategy address to set the whitelist status for
    /// @param whitelisted The whitelist status to set
    function setStrategyWhitelist(address strategyAddress, bool whitelisted) external;

    /// @notice Returns the whitelisted strategies
    /// @return The whitelisted strategies
    function isStrategyWhitelisted(address strategy) external view returns (bool);

    /// @notice Returns the operator set for a coverage agent
    /// @param coverageAgent The coverage agent to get the operator set for
    /// @return operatorSetId The operator set id for the coverage agent
    function getOperatorSetId(address coverageAgent) external view returns (uint32 operatorSetId);

    /// @notice Returns the coverage allocated to a coverage agent for a specified strategy
    /// @param operator The operator to get the coverage allocated for
    /// @param strategy The strategy to get the coverage allocated for
    /// @param coverageAgent The coverage agent to get the coverage allocated for
    /// @return coverageAllocated The coverage allocated in the units of the coverage agent's asset
    function coverageAllocated(address operator, address strategy, address coverageAgent) external view returns (uint256);
}
