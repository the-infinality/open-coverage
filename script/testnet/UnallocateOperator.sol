// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenHelper} from "../../utils/EigenHelper.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";

/// @title UnallocateOperator
/// @notice Script for an operator to deallocate (set to zero) all of their stake from every operator set
///         and strategy they are currently allocated in. Uses AllocationManager.modifyAllocations
///         with newMagnitudes = 0 for each allocation.
/// @dev Run with --sender <operator>. Caller must have permission to modify allocations for the operator
///      (typically the operator themselves). Skips operator sets where there is nothing to deallocate.
///
/// Timing: The tx is immediate. If the allocation was slashable, the deallocated amount remains
/// slashable for DEALLOCATION_DELAY blocks (chain-specific, e.g. ~1 day on devnet); after that it
/// is fully freed. If not slashable, the deallocation takes effect in the same block.
contract UnallocateOperator is Script, EigenHelper {
    function run() public returns (uint256 paramsCount) {
        address operator = msg.sender;
        IAllocationManager allocationManager = _getAllocationManager();

        console.log("Operator (sender):", operator);
        console.log("AllocationManager:", address(allocationManager));

        OperatorSet[] memory sets = allocationManager.getAllocatedSets(operator);
        require(sets.length > 0, "UnallocateOperator: no allocated sets");

        // Count operator sets that have at least one strategy with non-zero (effective) allocation
        paramsCount = 0;
        for (uint256 i = 0; i < sets.length; i++) {
            if (_hasNonZeroAllocation(allocationManager, operator, sets[i])) {
                paramsCount++;
            }
        }

        require(paramsCount > 0, "UnallocateOperator: no non-zero allocations to deallocate");

        IAllocationManagerTypes.AllocateParams[] memory params =
            new IAllocationManagerTypes.AllocateParams[](paramsCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < sets.length; i++) {
            if (!_hasNonZeroAllocation(allocationManager, operator, sets[i])) continue;

            IStrategy[] memory strategies = allocationManager.getAllocatedStrategies(operator, sets[i]);
            uint64[] memory zeroMagnitudes = new uint64[](strategies.length);
            for (uint256 j = 0; j < strategies.length; j++) {
                zeroMagnitudes[j] = 0;
            }
            params[idx] = IAllocationManagerTypes.AllocateParams({
                operatorSet: sets[i],
                strategies: strategies,
                newMagnitudes: zeroMagnitudes
            });
            idx++;
            console.log("  Deallocate from operator set:");
            console.log("    avs:", sets[i].avs);
            console.log("    id:", sets[i].id);
            console.log("    strategies:", strategies.length);
        }

        vm.startBroadcast();
        allocationManager.modifyAllocations(operator, params);
        vm.stopBroadcast();

        uint32 deallocationDelay = allocationManager.DEALLOCATION_DELAY();
        console.log("Unallocated from %s operator set(s).", paramsCount);
        console.log("DEALLOCATION_DELAY (blocks):", deallocationDelay);
        console.log("If allocations were slashable, they remain slashable for this many blocks; then fully freed.");
        return paramsCount;
    }

    function _hasNonZeroAllocation(
        IAllocationManager allocationManager,
        address operator,
        OperatorSet memory operatorSet
    ) internal view returns (bool) {
        IStrategy[] memory strategies = allocationManager.getAllocatedStrategies(operator, operatorSet);
        for (uint256 j = 0; j < strategies.length; j++) {
            IAllocationManagerTypes.Allocation memory a =
                allocationManager.getAllocation(operator, operatorSet, strategies[j]);
            if (_effectiveMagnitude(a) > 0) return true;
        }
        return false;
    }

    function _effectiveMagnitude(IAllocationManagerTypes.Allocation memory a) internal view returns (uint64) {
        int256 effective = int256(uint256(a.currentMagnitude));
        if (a.effectBlock != 0 && block.number >= a.effectBlock) {
            effective += a.pendingDiff;
        }
        return effective > 0 ? uint64(uint256(effective)) : 0;
    }
}
