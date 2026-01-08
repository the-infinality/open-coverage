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
    function coverageAllocated(address operator, address strategy, address coverageAgent)
        external
        view
        returns (uint256);

    /// @notice Captures rewards for a given claim based on the refund policy
    /// @dev Can be called by anyone
    /// @param claimId The id of the claim to capture rewards for
    function captureRewards(uint256 claimId)
        external
        returns (uint256 amount, uint32 duration, uint32 distributionStartTime);

    /// @notice Updates the metadata URI for this AVS
    /// @dev Only callable by the contract owner
    /// @param metadataURI The new metadata URI
    function updateAVSMetadataURI(string calldata metadataURI) external;

    /// @notice Slashes an operator's allocated stake through EigenLayer and claims redistributed tokens
    /// @dev Only callable internally by the diamond
    /// @param operator The operator to slash
    /// @param strategy The strategy to slash
    /// @param coverageAgent The coverage agent associated with the slash
    /// @param amount The amount to slash in coverage asset terms
    /// @return tokensReceived The amount of tokens received from the slash
    function slashOperator(address operator, address strategy, address coverageAgent, uint256 amount)
        external
        returns (uint256 tokensReceived);

    /// @notice Ensures strategy is added to the operator set and operator has non-zero allocations for given operator.
    /// @param operator The operator to verify allocations for
    /// @param coverageAgent The coverage agent whose operator set to check
    /// @param strategy The strategy to ensure is allocated
    function ensureAllocations(address operator, address coverageAgent, address strategy) external;

    /// @notice Returns the strategies allocated to by any operator for a coverage agent
    /// @param operator The operator to get the allocated strategies for
    /// @param coverageAgent The coverage agent to get the allocated strategies for
    /// @return strategies The strategy addresses allocated to
    function getAllocationedStrategies(address operator, address coverageAgent) external view returns (address[] memory);
}
