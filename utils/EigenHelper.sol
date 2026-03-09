// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {getConfig} from "./Config.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAllocationManager} from "eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPermissionController} from "eigenlayer-contracts/interfaces/IPermissionController.sol";
import {IStrategyFactory} from "eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategy.sol";


struct EigenAddresses {
    address allocationManager;
    address delegationManager;
    address strategyManager;
    address rewardsCoordinator;
    address permissionController;
    address strategyFactory;
    address testStrategy;
}

struct EigenAddressbook {
    EigenAddresses eigenAddresses;
}


contract EigenHelper {
    using stdJson for string;

    string public constant EIGEN_CONFIG_SUFFIX = "eigen";

    constructor() {
        _labelAddresses(_getAddressBook());
    }

    function _getAllocationManager() internal view returns (IAllocationManager) {
        return IAllocationManager(_getAddressBook().eigenAddresses.allocationManager);
    }
    function _getDelegationManager() internal view returns (IDelegationManager) {
        return IDelegationManager(_getAddressBook().eigenAddresses.delegationManager);
    }
    function _getStrategyManager() internal view returns (IStrategyManager) {
        return IStrategyManager(_getAddressBook().eigenAddresses.strategyManager);
    }
    function _getRewardsCoordinator() internal view returns (IRewardsCoordinator) {
        return IRewardsCoordinator(_getAddressBook().eigenAddresses.rewardsCoordinator);
    }
    function _getPermissionController() internal view returns (IPermissionController) {
        return IPermissionController(_getAddressBook().eigenAddresses.permissionController);
    }
    function _getStrategyFactory() internal view returns (IStrategyFactory) {
        return IStrategyFactory(_getAddressBook().eigenAddresses.strategyFactory);
    }
    function _getTestStrategy() internal view returns (IStrategy) {
        return IStrategy(_getAddressBook().eigenAddresses.testStrategy);
    }

    /// @notice Returns the WETH strategy from config (strategies.WETH). Falls back to testStrategy if WETH not set (e.g. mainnet).
    function _getWethStrategy() internal view returns (IStrategy) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory configJson = getConfig(EIGEN_CONFIG_SUFFIX);
        string memory path = string.concat("$['", vm.toString(block.chainid), "'].strategies.WETH");
        if (configJson.keyExists(path)) {
            address wethStrategy = configJson.readAddress(path);
            if (wethStrategy != address(0)) return IStrategy(wethStrategy);
        }
        return _getTestStrategy();
    }

    function _getAddressBook() internal view returns (EigenAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = getConfig(EIGEN_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        ab.eigenAddresses.allocationManager =
            configJson.readAddress(string.concat(selectorPrefix, ".allocationManager"));
        ab.eigenAddresses.delegationManager =
            configJson.readAddress(string.concat(selectorPrefix, ".delegationManager"));
        ab.eigenAddresses.strategyManager = configJson.readAddress(string.concat(selectorPrefix, ".strategyManager"));
        ab.eigenAddresses.rewardsCoordinator =
            configJson.readAddress(string.concat(selectorPrefix, ".rewardsCoordinator"));
        ab.eigenAddresses.permissionController =
            configJson.readAddress(string.concat(selectorPrefix, ".permissionsController"));
        ab.eigenAddresses.strategyFactory = configJson.readAddress(string.concat(selectorPrefix, ".strategyFactory"));
        ab.eigenAddresses.testStrategy = configJson.readAddress(string.concat(selectorPrefix, ".testStrategy"));
    }

    function _labelAddresses(EigenAddressbook memory ab) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.label(ab.eigenAddresses.allocationManager, "Allocation Manager");
        vm.label(ab.eigenAddresses.delegationManager, "Delegation Manager");
        vm.label(ab.eigenAddresses.strategyManager, "Strategy Manager");
        vm.label(ab.eigenAddresses.rewardsCoordinator, "Rewards Coordinator");
        vm.label(ab.eigenAddresses.permissionController, "Permission Controller");
        vm.label(ab.eigenAddresses.strategyFactory, "Strategy Factory");
        vm.label(ab.eigenAddresses.testStrategy, "Test Strategy");
        string memory configJson = getConfig(EIGEN_CONFIG_SUFFIX);
        string memory wethStrategyPath = string.concat("$['", vm.toString(block.chainid), "'].strategies.WETH");
        if (configJson.keyExists(wethStrategyPath)) {
            address wethStrategy = configJson.readAddress(wethStrategyPath);
            if (wethStrategy != address(0)) vm.label(wethStrategy, "WETH Strategy");
        }
    }
}
