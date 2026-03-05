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

    /// @notice Get the coordinator that manages the coverage agent
    /// @dev The coordinator must be represented by an address and could be a contract or an account.
    /// @return coordinator The coordinator address.
    function coordinator() external view returns (address);

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

    /// @notice Slash a coverage purchase up to a specified amount.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @dev Should slash the coverage purchase and track the amount of coverage slashed for future slashing purposes.
    /// @dev Loops through claims in order, slashing each until the total slashed reaches the specified amount.
    /// @param coverageId The id of the coverage purchase to slash.
    /// @param amount The maximum amount to slash across all claims in this coverage.
    /// @param deadline The deadline timestamp passed to slashClaims (e.g. block.timestamp + buffer).
    /// @return slashStatuses The status of each claim after slashing (may be unchanged if not slashed).
    /// @return totalSlashed The total amount actually slashed across all claims.
    function slashCoverage(uint256 coverageId, uint256 amount, uint256 deadline)
        external
        returns (CoverageClaimStatus[] memory slashStatuses, uint256 totalSlashed);

    /// @notice Repay slashed coverage up to a specified amount.
    /// @dev Should loop through claims in order, repaying each until the total repaid reaches the specified amount.
    /// @param coverageId The id of the coverage purchase to repay.
    /// @param amount The maximum amount to repay across all claims in this coverage.
    function repaySlashedCoverage(uint256 coverageId, uint256 amount) external;

    /// @notice Get the amounts of each claim owing after slashing.
    /// @dev Should return the amounts of each claim owing after slashing.
    /// @param coverageId The id of the coverage purchase to get the owing claims for.
    /// @return amounts The amounts of each claim owing after slashing.
    function repaymentsOwing(uint256 coverageId) external view returns (uint256[] memory amounts, uint256 totalOwing);

    /// @notice Update the metadata of the coverage agent.
    /// @dev Can only be called by the coverage agent coordinator.
    /// @param metadataURI The new metadata URI.
    function updateMetadata(string calldata metadataURI) external;
}
