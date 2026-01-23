// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICoverageAgent, ClaimCoverageRequest} from "./ICoverageAgent.sol";
import {CoverageClaimStatus} from "./ICoverageProvider.sol";

/// @title IExampleCoverageAgent
/// @author p-dealwis, Infinality
/// @notice An interface for the example coverage agent implementation.
/// @dev Extends ICoverageAgent with specific functions for purchasing, reserving, and slashing coverage.
interface IExampleCoverageAgent is ICoverageAgent {
    error NotCoverageAgentCoordinator();

    /// @notice Purchase coverage from coverage providers.
    /// @dev Can only be called by the coverage agent coordinator. Should track the amount of coverage purchased for future slashing purposes.
    /// @param requests The requests to purchase coverage.
    /// @return coverageId The id of the coverage purchased.
    function purchaseCoverage(ClaimCoverageRequest[] calldata requests) external returns (uint256 coverageId);

    /// @notice Reserve coverage from coverage providers.
    /// @dev Can only be called by the coverage agent coordinator. Creates reservations without immediate reward payment.
    /// @param requests The requests to reserve coverage.
    /// @return coverageId The id of the reserved coverage.
    function reserveCoverage(ClaimCoverageRequest[] calldata requests) external returns (uint256 coverageId);

    /// @notice Convert reserved coverage to issued coverage.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @param coverageId The id of the reserved coverage to convert.
    /// @param requests The requests to convert. Only duration, amount, and reward need to be filled.
    ///        coverageProvider and positionId are taken from the original reservation.
    function convertReservedCoverage(uint256 coverageId, ClaimCoverageRequest[] calldata requests) external;

    /// @notice Slash a coverage purchase.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @dev Should slash the coverage purchase and track the amount of coverage slashed for future slashing purposes.
    /// @param coverageId The id of the coverage purchase to slash.
    /// @return slashStatuses The status of each claim after slashing.
    function slashCoverage(uint256 coverageId) external returns (CoverageClaimStatus[] memory slashStatuses);
}
