// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ExampleCoverageAgent} from "../src/ExampleCoverageAgent.sol";
import {ChainHelper} from "../utils/ChainHelper.sol";

/// @title DeployExampleCoverageAgent
/// @notice Script to deploy ExampleCoverageAgent contract
/// @dev The sender (msg.sender) will be set as the coordinator
contract DeployExampleCoverageAgent is Script, ChainHelper {
    function run() public returns (address exampleCoverageAgentAddress) {
        vm.startBroadcast();

        address coordinator = msg.sender;
        address coverageAsset = vm.envOr("COVERAGE_ASSET", _getUSDC());

        ExampleCoverageAgent exampleCoverageAgent = new ExampleCoverageAgent(coordinator, coverageAsset);
        exampleCoverageAgentAddress = address(exampleCoverageAgent);

        console.log("\n=== Deployment Summary ===");
        console.log("ExampleCoverageAgent deployed at:", exampleCoverageAgentAddress);
        console.log("Coordinator:", coordinator);
        console.log("Coverage Asset:", coverageAsset);

        vm.stopBroadcast();
    }
}
