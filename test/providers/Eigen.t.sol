// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EigenTestDeployer} from "../utils/EigenTestDeployer.sol";
import {CoverageManagerData} from "src/interfaces/ICoveragePool.sol";
import {CoveragePosition, Refundable} from "src/interfaces/ICoverageManager.sol";
import {CreatePositionAddtionalData} from "src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {OperatorSet} from "eigenlayer-contracts/libraries/OperatorSetLib.sol";
import {EigenProviderMethods} from "utils/EigenProviderMethods.sol";
import {IEigenOperatorProxy} from "src/providers/eigenlayer/interfaces/IEigenOperatorProxy.sol";

contract EigenTest is EigenTestDeployer {
    IEigenOperatorProxy public operator;

    function _setupwithAllocations() internal {
        vm.roll(block.number + 126001);
        operator.registerCoveragePool(address(eigenCoverageManager), address(coveragePool), 0);
        address[] memory strategyAddresses = new address[](1);
        strategyAddresses[0] = address(_getTestStrategy());
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1e18;
        operator.allocate(address(eigenCoverageManager), address(coveragePool), strategyAddresses, magnitudes);
    }

    function setUp() public override {
        super.setUp();

        operator = IEigenOperatorProxy(
            EigenProviderMethods.createOperatorProxy(
                eigenOperatorInstance, eigenCoverageManager.eigenAddresses(), address(this), ""
            )
        );

        IPermissionController(eigenCoverageManager.eigenAddresses().permissionController).acceptAdmin(address(operator));

        coveragePool.registerCoverageManager(address(eigenCoverageManager));
        eigenCoverageManager.setStrategyWhitelist(address(_getTestStrategy()), true);
    }

    function test_checkCoverageManagerRegistered() public view {
        CoverageManagerData memory coverageManagerData = coveragePool.coverageManagerData(address(eigenCoverageManager));
        assertEq(coverageManagerData.active, true);
    }

    function test_registerCoveragePool() public {
        operator.registerCoveragePool(address(eigenCoverageManager), address(coveragePool), 10000);
    }

    function test_allocate() public {
        _setupwithAllocations();
        OperatorSet memory operatorSet = OperatorSet({
            avs: address(eigenCoverageManager), id: eigenCoverageManager.getOperatorSetId(address(coveragePool))
        });
        IAllocationManagerTypes.Allocation memory allocation = IAllocationManager(
                eigenCoverageManager.eigenAddresses().allocationManager
            ).getAllocation(address(operator), operatorSet, _getTestStrategy());
        assertEq(allocation.currentMagnitude, 1e18);
    }

    function test_createPosition() public {
        _setupwithAllocations();

        CoveragePosition memory data = CoveragePosition({
            minRate: 100,
            maxDuration: 30 days,
            expiryTimestamp: block.timestamp + 365 days,
            asset: address(_getTestStrategy().underlyingToken()),
            refundable: Refundable.None,
            slashCoordinator: address(0)
        });
        bytes memory additionalData = abi.encode(
            CreatePositionAddtionalData({operator: address(operator), strategy: address(_getTestStrategy())})
        );
        uint256 positionId = eigenCoverageManager.createPosition(address(coveragePool), data, additionalData);
        assertEq(positionId, 0);
    }
}
