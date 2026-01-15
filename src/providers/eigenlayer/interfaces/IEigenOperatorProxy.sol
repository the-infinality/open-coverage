// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EigenAddresses} from "../Types.sol";

interface IEigenOperatorProxy {
    /// @dev Error thrown when the caller is not the service manager
    error NotServiceManager();
    /// @dev Error thrown when the caller is not the operator
    error NotOperator();
    /// @dev Error thrown when the operator is already allocated to a strategy
    error AlreadyAllocated();
    /// @dev Error thrown when the caller is not the restaker
    error NotRestaker();
    /// @dev Error thrown when the operator is already registered
    error AlreadyRegistered();
    /// @dev Error thrown when the staker is the zero address
    error ZeroAddress();

    /// @notice Register a coverage agent to the operator
    /// @param serviceManager_ The service manager to register the coverage agent to
    /// @param coverageAgent_ The coverage agent to register
    /// @param rewardsSplit_ The rewards split to set for the coverage agent
    function registerCoverageAgent(address serviceManager_, address coverageAgent_, uint16 rewardsSplit_) external;

    /// @notice Update the operator metadata URI
    /// @param _metadataUri The new metadata URI
    function updateOperatorMetadataURI(string calldata _metadataUri) external;

    /// @notice Allocate the operator set to the strategy, called by service manager.
    /// @dev Can only be called after ALLOCATION_CONFIGURATION_DELAY (approximately 17.5 days) has passed since registration.
    /// @param serviceManager_ The service manager to allocate to
    /// @param coverageAgent_ The coverage agent to allocate to
    /// @param _strategyAddresses Strategy addresses
    function allocate(
        address serviceManager_,
        address coverageAgent_,
        address[] calldata _strategyAddresses,
        uint64[] calldata _magnitudes
    ) external;

    /// @notice Get the handler for the operator proxy
    /// @return handler The handler's address administating the operator proxy.
    function handler() external view returns (address handler);
}
