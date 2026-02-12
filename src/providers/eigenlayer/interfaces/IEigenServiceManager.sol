// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";
import {EigenAddresses} from "../Types.sol";

/// @notice An interface for the Eigen coverage provider.
interface IEigenServiceManager {
    error StrategyAssetAlreadyRegistered(address asset);
    error CoverageAgentAlreadyRegistered();
    error InvalidAVS(address avs);
    error NotOperatorAuthorized(address operator, address handler);
    error NotAllocated(address operator, address strategy, address coverageAgent);

    /// @notice The threshold exceeds the maximum allowed (10000 = 100%).
    error ThresholdExceedsMax(uint16 maxThreshold, uint16 threshold);

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

    /// @notice Submits an operator-directed reward to the RewardsCoordinator
    /// @dev Can be called by other facets to distribute rewards to operators
    /// @dev If startTimestamp is 0, calculates distributionStartTime automatically using the next interval to avoid retroactive submissions
    /// @dev If duration is 0, uses CALCULATION_INTERVAL_SECONDS as the duration
    /// @param operator The operator to reward
    /// @param strategy The strategy associated with the reward
    /// @param token The token to distribute as reward
    /// @param amount The amount of tokens to reward
    /// @param startTimestamp The start timestamp (0 to auto-calculate using next interval)
    /// @param duration The duration of the reward distribution (0 to use calculation interval)
    /// @param description Description of the reward
    function submitOperatorReward(
        address operator,
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        uint32 startTimestamp,
        uint32 duration,
        string memory description
    ) external returns (uint32 resolvedDistributionStartTime, uint32 resolvedDuration);

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

    /// @notice Sets the coverage threshold for an operator
    /// @param operator The operator to set the coverage threshold for
    /// @param coverageThreshold The coverage threshold to set for the operator
    function setCoverageThreshold(address operator, uint16 coverageThreshold) external;

    /// @notice Returns the coverage threshold for an operator
    /// @param operator The operator to get the coverage threshold for
    /// @return coverageThreshold The coverage threshold for the operator
    function coverageThreshold(address operator) external view returns (uint16 coverageThreshold);

    /// @notice Sets the liquidation threshold for the coverage provider.
    /// @param threshold The liquidation threshold to set for the coverage provider.
    function setLiquidationThreshold(uint16 threshold) external;

    /// @notice Returns the strategies allocated to by any operator for a coverage agent
    /// @param operator The operator to get the allocated strategies for
    /// @param coverageAgent The coverage agent to get the allocated strategies for
    /// @return strategies The strategy addresses allocated to
    function getAllocationedStrategies(address operator, address coverageAgent) external view returns (address[] memory);

    /// @notice Returns the whitelisted strategies
    /// @return strategies The whitelisted strategies
    function whitelistedStrategies() external view returns (address[] memory strategies);
}
