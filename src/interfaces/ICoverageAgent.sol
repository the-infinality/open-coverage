// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct CoverageProviderData {
    bool active;
}

struct ClaimCoverageRequest {
    /// @notice Address of the coverage provider to claim coverage from.
    address coverageProvider;
    /// @notice The coverage position to claim coverage from.
    uint256 positionId;
    /// @notice The amount of coverage to claim in the units of the agent's asset.
    uint256 amount;
    /// @notice The reward for the coverage provider
    uint256 reward;
    /// @notice The duration of the coverage to claim.
    uint256 duration;
}

struct Claim {
    uint256 positionId;
    uint256 claimId;
}

struct Coverage {
    Claim[] claims;
}

/// @title ICoverageAgent
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage agent.
interface ICoverageAgent {
    event CoverageProviderRegistered(address indexed coverageProvider);
    event PositionRegistered(address indexed coverageProvider, uint256 indexed positionId);

    /// ============ Coverage Providers ============

    /// @notice Register a coverage provider.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @param coverageProvider The coverage provider to register.
    function registerCoverageProvider(address coverageProvider) external;

    /// @notice Triggered when a coverage position has been registered with a coverage provider.
    /// @dev A coverage position is a guarantee from the coverage provider to provide coverage within their given parameters.
    /// @param positionId The coverage position to register.
    function onRegisterPosition(uint256 positionId) external;

    /// ============ Coverage ============

    /// @notice Purchase coverage from coverage providers.
    /// @dev Can only be called by the coverage agent coordinator. Should track the amount of coverage purchased for future slashing purposes.
    /// @param requests The requests to purchase coverage.
    /// @return coverageId The id of the coverage purchased.
    function purchaseCoverage(ClaimCoverageRequest[] calldata requests) external returns (uint256 coverageId);

    /// ============ Discovery ============

    /// @notice Get the coverage providers registered with the coverage agent.
    /// @return coverageProviderAddresses The coverage providers.
    function registeredCoverageProviders() external view returns (address[] memory coverageProviderAddresses);

    /// @notice Get the coverage provider data
    /// @param coverageProvider The coverage provider to get the data for.
    /// @return data The coverage provider data.
    function coverageProviderData(address coverageProvider) external view returns (CoverageProviderData memory data);

    /// @notice Get the coverage for a given coverage id.
    /// @param coverageId The coverage id to get the coverage for.
    /// @return coverage The coverage data
    function coverage(uint256 coverageId) external view returns (Coverage memory coverage);

    /// @notice Get the asset that the coverage agent requires coverage on
    /// @dev The asset must be an ERC20 token. Rewards will be paid in this asset.
    /// @return asset The asset address.
    function asset() external view returns (address);

    /// @notice Get the entity that the coverage agent is covering
    /// @dev The entity must be represented by an address and could be a contract or an account.
    /// @return entity The entity address.
    function entity() external view returns (address);
}
