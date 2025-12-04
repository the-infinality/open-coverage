// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct CoverageManagerData {
    bool active;
}

struct PurchaseCoverageRequest {
    address coverageManager;
    uint256 positionId;
    uint256 amount;
    uint256 premium;
    uint256 duration;
}

struct Claim {
    uint256 positionId;
    uint256 claimId;
}

struct Coverage {
    Claim[] claims;
}

/// @title ICoveragePool
/// @author p-dealwis, Infinality
/// @notice An interface for a coverage pool.
interface ICoveragePool {
    event CoverageManagerRegistered(address indexed coverageManager);
    event PositionRegistered(address indexed coverageManager, uint256 indexed positionId);

    /// ============ Coverage Managers ============

    /// @notice Register a coverage manager.
    /// @dev Can only be called by the coverage pool coordinator.
    /// @param coverageManager The coverage manager to register.
    function registerCoverageManager(address coverageManager) external;

    /// @notice Triggered when a coverage position has been registered with a coverage manager.
    /// @dev A coverage position is a guarantee from the coverage manager to provide coverage within their given parameters.
    /// @param positionId The coverage position to register.
    function onRegisterPosition(uint256 positionId) external;

    /// ============ Coverage ============

    /// @notice Purchase coverage from coverage managers.
    /// @dev Can only be called by the coverage pool coordinator. Should track the amount of coverage purchased for future slashing purposes.
    /// @param requests The requests to purchase coverage.
    /// @return coverageId The id of the coverage purchased.
    function purchaseCoverage(PurchaseCoverageRequest[] calldata requests) external returns (uint256 coverageId);


    /// ============ Discovery ============

    /// @notice Get the coverage managers registered with the coverage pool.
    /// @return coverageManagerAddresses The coverage managers.
    function registeredCoverageManagers() external view returns (address[] memory coverageManagerAddresses);

    /// @notice Get the coverage manager data
    /// @param coverageManager The coverage manager to get the data for.
    /// @return data The coverage manager data.
    function coverageManagerData(address coverageManager) external view returns (CoverageManagerData memory data);

    /// @notice Get the coverage for a given coverage id.
    /// @param coverageId The coverage id to get the coverage for.
    /// @return coverage The coverage data
    function coverage(uint256 coverageId) external view returns (Coverage memory coverage);

    // /// @notice Get the positions for a given coverage manager.
    // /// @param coverageManager The coverage manager to get the positions for.
    // /// @return positionIds The position ids.
    // function positions(address coverageManager) external view returns (uint256[] memory positionIds);
}
