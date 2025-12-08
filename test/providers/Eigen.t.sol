// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "../utils/TestDeployer.sol";
import {CoverageManagerData} from "src/interfaces/ICoveragePool.sol";
import {CoveragePosition} from "src/interfaces/ICoverageManager.sol";
import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";
import {CreatePositionAddtionalData} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
contract EigenTest is TestDeployer {
    EigenOperatorProxy operatorProxy;

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operatorProxy.registerCoveragePool(address(coveragePool), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operatorProxy.allocate(address(coveragePool), strategyAddresses, magnitudes);
    }

    function setUp() public override {
        super.setUp();
        operatorProxy = EigenOperatorProxy(eigenCoverageManager.createOperatorProxy(""));

        coveragePool.registerCoverageManager(address(eigenCoverageManager));
        eigenCoverageManager.setStrategyWhitelist(address(_getTestStrategy()), true);
    }

    function test_checkCoverageManagerRegistered() public view {
        CoverageManagerData memory coverageManagerData = coveragePool.coverageManagerData(address(eigenCoverageManager));
        assertEq(coverageManagerData.active, true);
    }

    function test_registerCoveragePool() public {
        operatorProxy.registerCoveragePool(address(coveragePool), 10000);
    }

    function test_allocate() public {
        _setupwithAllocations();
        OperatorSet memory operatorSet = OperatorSet({avs: address(eigenCoverageManager), id: eigenCoverageManager.getOperatorSetId(address(coveragePool))});
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(eigenCoverageManager.eigenAddresses().allocationManager).getAllocation(address(operatorProxy), operatorSet, _getTestStrategy());
        assertEq(allocation.currentMagnitude, 1e18);
    }

    // function test_createPosition() public {
    //     _setupwithAllocations();

    //     CoveragePosition memory data = CoveragePosition({
    //         minRate: 100,
    //         maxDuration: 30 days,
    //         expiryTimestamp: block.timestamp + 365 days,
    //         asset: address(_getTestStrategy().underlyingToken()),
    //         refundable: false,
    //         slashCoordinator: address(0)
    //     });
    //     bytes memory additionalData = abi.encode(CreatePositionAddtionalData({operatorProxy: address(operatorProxy), strategy: address(_getTestStrategy())}));
    //     uint256 positionId = eigenCoverageManager.createPosition(address(coveragePool), data, additionalData);
    //     assertEq(positionId, 1);
    // }
}
