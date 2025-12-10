// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
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
    address coverageAgent;
}

struct OperatorData {
    mapping(address => uint256) coverageAgentAmount;
    bool active;
}

/// @notice An interface for the Eigen coverage provider.
interface IEigenServiceManager {
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
}
