// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";


function getConfig(string memory suffix) view returns (string memory configJson) {
    Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string memory configPath = string.concat("config/", suffix, ".json");
    configJson = vm.readFile(configPath);
}
