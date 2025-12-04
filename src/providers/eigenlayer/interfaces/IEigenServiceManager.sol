// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {EigenAddresses} from "../Types.sol";

/// @notice An interface for the Eigen coverage manager.
interface IEigenServiceManager {
    function eigenAddresses() external view returns (EigenAddresses memory);

    /// @notice Creates a new operator for a coverage pool
    /// @param _operatorMetadata The metadata for the operator
    /// @return operator The address of the created operator
    function createOperatorProxy(string calldata _operatorMetadata)
        external
        returns (address operator);
    
    /**
     * @notice Registers an operator to the AVS, called by the Allocation Manager contract (access control set for the allocation manager).
     * @param _operator The operator to register
     * @param _avs The AVS to register the operator to
     * @param _operatorSetIds The operator set ids to register the operator to
     * @param _data Additional data
     */
    function registerOperator(address _operator, address _avs, uint32[] calldata _operatorSetIds, bytes calldata _data)
        external;

    /// @notice Returns the created at epoch for an operator
    /// @param operator The operator to get the created at epoch for
    /// @return The created at epoch of the operator
    function createdAtEpoch(address operator) external view returns (uint32);

    /// @notice Returns the calculation interval seconds
    /// @return The calculation interval seconds
    function calculationIntervalSeconds() external view returns (uint256);

    /// @notice Sets the whitelist status for a strategy
    /// @param strategyAddress The strategy address to set the whitelist status for
    /// @param whitelisted The whitelist status to set
    function setStrategyWhitelist(address strategyAddress, bool whitelisted) external;

    /// @notice Returns the whitelisted strategies
    /// @return The whitelisted strategies
    function isStrategyWhitelisted(address strategy) external view returns (bool);

    /// @notice Returns the operator set for a coverage pool
    /// @param coveragePool The coverage pool to get the operator set for
    /// @return operatorSetId The operator set id for the coverage pool
    function getOperatorSetId(address coveragePool) external view returns (uint32 operatorSetId);
}
