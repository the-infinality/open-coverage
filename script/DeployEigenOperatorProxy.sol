// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenHelper, EigenAddressbook} from "../utils/EigenHelper.sol";
import {EigenOperatorProxy} from "../src/providers/eigenlayer/EigenOperatorProxy.sol";
import {EigenAddresses} from "../src/providers/eigenlayer/Types.sol";

/// @title DeployEigenOperatorProxy
/// @notice Script to deploy EigenOperatorProxy contract
/// @dev The sender (msg.sender) will be set as the handler
contract DeployEigenOperatorProxy is Script, EigenHelper {
    function run() public returns (address eigenOperatorProxyAddress) {
        vm.startBroadcast();

        address handler = msg.sender;
        string memory operatorMetadata =
            vm.envOr("OPERATOR_METADATA_URI", string("https://coverage.example.com/operator.json"));

        EigenAddressbook memory eigenAddressBook = _getAddressBook();

        EigenAddresses memory eigenAddresses = EigenAddresses({
            allocationManager: eigenAddressBook.eigenAddresses.allocationManager,
            delegationManager: eigenAddressBook.eigenAddresses.delegationManager,
            strategyManager: eigenAddressBook.eigenAddresses.strategyManager,
            rewardsCoordinator: eigenAddressBook.eigenAddresses.rewardsCoordinator,
            permissionController: eigenAddressBook.eigenAddresses.permissionController
        });

        EigenOperatorProxy eigenOperatorProxy = new EigenOperatorProxy(eigenAddresses, handler, operatorMetadata);
        eigenOperatorProxyAddress = address(eigenOperatorProxy);

        console.log("\n=== Deployment Summary ===");
        console.log("EigenOperatorProxy deployed at:", eigenOperatorProxyAddress);
        console.log("Handler:", handler);
        console.log("Operator Metadata:", operatorMetadata);

        vm.stopBroadcast();

        return eigenOperatorProxyAddress;
    }
}
