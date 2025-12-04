// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestDeployer} from "../utils/TestDeployer.sol";
import {CoverageManagerData} from "src/interfaces/ICoveragePool.sol";
import {EigenOperatorProxy} from "src/providers/eigenlayer/EigenOperatorProxy.sol";

import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";

import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";

import {console} from "forge-std/console.sol";


contract EigenTest is TestDeployer {
    EigenOperatorProxy operatorProxy;

    function _setupwithAllocations() internal {
        operatorProxy.registerCoveragePool(address(coveragePool), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        operatorProxy.allocate(address(coveragePool), strategyAddresses);
    }

    function setUp() public override {
        super.setUp();
        operatorProxy = EigenOperatorProxy(eigenCoverageManager.createOperatorProxy(""));

        coveragePool.registerCoverageManager(address(eigenCoverageManager));
        eigenCoverageManager.setStrategyWhitelist(address(_getTestStrategy()), true);
    }

    function test_checkCoverageManagerRegistered() public {
        CoverageManagerData memory coverageManagerData = coveragePool.coverageManagerData(address(eigenCoverageManager));
        assertEq(coverageManagerData.active, true);
    }

    function test_registerCoveragePool() public {
        operatorProxy.registerCoveragePool(address(coveragePool), 10000);
    }

    function test_allocate() public {
        vm.roll(block.number + 126001);

        operatorProxy.registerCoveragePool(address(coveragePool), 10000);

        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());

        operatorProxy.allocate(address(coveragePool), strategyAddresses);
    }
}
