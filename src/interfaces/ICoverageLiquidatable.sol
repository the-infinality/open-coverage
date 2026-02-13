// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice An interface for a coverage provider that can liquidate a coverage claim.
interface ICoverageLiquidatable {
    /// @notice Emitted when a claim is liquidated.
    event ClaimLiquidated(uint256 indexed claimId, uint256 indexed oldPositionId, uint256 indexed newPositionId);
    /// @notice The threshold exceeds the maximum allowed (10000 = 100%).
    error ThresholdExceedsMax(uint16 maxThreshold, uint16 threshold);

    /// @notice The position's coverage percentage meets or exceeds the liquidation threshold.
    error MeetsLiquidationThreshold(uint16 liquidationThreshold, uint16 coveragePercentage);

    /// @notice Liquidate a coverage claim if it doesn't meet its obligations.
    /// @dev This should be called by the coverage agent if the coverage position doesn't meet its obligations.
    /// @param claimId The id of the coverage position to liquidate.
    /// @param positionId The id of the coverage position to replace the liquidated claim with.
    function liquidateClaim(uint256 claimId, uint256 positionId) external;

    /// @notice Get the liquidation threshold for the coverage provider.
    /// @return threshold The liquidation threshold for the coverage provider.
    function liquidationThreshold() external view returns (uint16 threshold);

    /// @notice Sets the liquidation threshold for the coverage provider.
    /// @param threshold The liquidation threshold to set for the coverage provider.
    function setLiquidationThreshold(uint16 threshold) external;

    /// @notice Returns the coverage threshold for an operator
    /// @param operatorId The operator to get the coverage threshold for
    /// @return coverageThreshold The coverage threshold for the operator
    function coverageThreshold(bytes32 operatorId) external view returns (uint16 coverageThreshold);

    /// @notice Sets the coverage threshold for an operator
    /// @param operatorId The operator id to set the coverage threshold for
    /// @param coverageThreshold The coverage threshold to set for the operator
    function setCoverageThreshold(bytes32 operatorId, uint16 coverageThreshold) external;
}
