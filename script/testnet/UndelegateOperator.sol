// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenHelper} from "../../utils/EigenHelper.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";

/// @title UndelegateOperator
/// @notice Script for a staker to undelegate from their current operator. Queues a withdrawal for all
///         of the staker's shares; complete the withdrawal later via DelegationManager to receive tokens.
/// @dev Reverts if the sender is not delegated, or if the sender is an operator (EigenLayer does not
///      allow operators to undelegate from themselves). Use --sender <staker> to run as the staker.
contract UndelegateOperator is Script, EigenHelper {
    function run() public returns (bytes32[] memory withdrawalRoots) {
        address staker = msg.sender;
        IDelegationManager delegationManager = _getDelegationManager();

        console.log("Staker (sender):", staker);
        console.log("DelegationManager:", address(delegationManager));

        require(delegationManager.isDelegated(staker), "UndelegateOperator: not delegated to any operator");
        require(
            !delegationManager.isOperator(staker), "UndelegateOperator: operators cannot undelegate from themselves"
        );

        address operator = delegationManager.delegatedTo(staker);
        console.log("Current operator:", operator);

        vm.startBroadcast();
        withdrawalRoots = delegationManager.undelegate(staker);
        vm.stopBroadcast();

        console.log("Undelegated. Withdrawal roots count:", withdrawalRoots.length);
        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            console.log("  [%s]:", i);
            console.logBytes32(withdrawalRoots[i]);
        }
        console.log(
            "\nComplete the queued withdrawal(s) via DelegationManager.completeQueuedWithdrawal when delay has passed."
        );

        return withdrawalRoots;
    }
}
