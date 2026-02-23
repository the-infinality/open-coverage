// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";


function getConfig(string memory suffix) view returns (string memory configJson) {
    Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string memory basePath = vm.envOr("OPEN_COVERAGE_CONFIG_BASE_PATH", string("config"));
    string memory configPath = string.concat(basePath, "/", suffix, ".json");
    configJson = vm.readFile(configPath);
}