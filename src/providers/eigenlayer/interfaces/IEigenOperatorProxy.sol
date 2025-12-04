// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

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

    /// @notice Initialize the EigenOperator
    /// @param _serviceManager EigenServiceManager address
    /// @param _handler Eigen operator proxies handler
    /// @param _metadata Metadata URI
    function initialize(address _serviceManager, address _handler, string calldata _metadata) external;

    /// @notice Register a coverage pool to the operator
    /// @param _coveragePool The coverage pool to register
    /// @param _rewardsSplit The rewards split to set for the coverage pool
    function registerCoveragePool(address _coveragePool, uint16 _rewardsSplit) external;

    /// @notice Update the operator metadata URI
    /// @param _metadataUri The new metadata URI
    function updateOperatorMetadataURI(string calldata _metadataUri) external;

    /// @notice Allocate the operator set to the strategy, called by service manager.
    /// @dev Can only be called after ALLOCATION_CONFIGURATION_DELAY (approximately 17.5 days) has passed since registration.
    /// @param coveragePool_ The coverage pool to allocate to
    /// @param _strategyAddresses Strategy addresses
    function allocate(address coveragePool_, address[] calldata _strategyAddresses) external;

    /// @notice Get the service manager
    /// @return The service manager address
    function eigenServiceManager() external view returns (address);

    /// @notice Get the handler for the operator proxy
    /// @return handler The handler's address administating the operator proxy.
    function handler() external view returns (address handler);

    // /// @notice Advance the TOTP
    // function advanceTotp() external;

    // /**
    //  * @notice Implements the IERC1271 interface to validate signatures
    //  * @dev In this implementation, we check if the digest hash is directly allowlisted
    //  * @param digest The digest hash containing encoded delegation information
    //  * @return magicValue Returns the ERC1271 magic value if valid, or 0xffffffff if invalid
    //  */
    // function isValidSignature(bytes32 digest, bytes memory signature) external view returns (bytes4 magicValue);

    // /// @notice Get the current TOTP
    // /// @return The current TOTP
    // function currentTotp() external view returns (uint256);

    // /// @notice Get the current TOTP expiry timestamp
    // /// @return The current TOTP expiry timestamp
    // function getCurrentTotpExpiryTimestamp() external view returns (uint256);

    // /// @notice Calculate the TOTP digest hash
    // /// @param _staker The staker address
    // /// @param _operator The operator address
    // /// @return The TOTP digest hash
    // function calculateTotpDigestHash(address _staker, address _operator) external view returns (bytes32);

    // /// @notice Get the restaker
    // /// @return The restaker address
    // function restaker() external view returns (address);
}
