// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/// @title IDiamondOwner
/// @notice Interface for getting the diamond owner
/// @dev Adds formal ownership functionality
interface IDiamondOwner {
    /// @notice Gets the diamond owner
    /// @dev As specified in EIP-2535. This function returns the address of the contract owner.
    /// @return owner_ The address of the contract owner
    function owner() external view returns (address owner_);

    /// @notice Sets the diamond owner
    function setOwner(address newOwner) external;
}

