// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {getConfig} from "utils/Config.sol";

contract TestDeployer is Test {
    using stdJson for string;

    string public constant CHAIN_CONFIG_SUFFIX = "chains";

    address owner = address(this);

    address USDC;
    address USDT;
    address WETH;
    address rETH;

    function setUp() public virtual {
        string memory chainJson = getConfig(CHAIN_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        vm.createSelectFork(
            chainJson.readString(string.concat(selectorPrefix, ".name")),
            chainJson.readUint(string.concat(selectorPrefix, ".fromBlockNumber"))
        );

        USDC = chainJson.readAddress(string.concat(selectorPrefix, ".assets.USDC"));
        USDT = chainJson.readAddress(string.concat(selectorPrefix, ".assets.USDT"));
        WETH = chainJson.readAddress(string.concat(selectorPrefix, ".assets.WETH"));
        rETH = chainJson.readAddress(string.concat(selectorPrefix, ".assets.rETH"));

        vm.label(USDC, "USDC");
        vm.label(USDT, "USDT");
        vm.label(WETH, "WETH");
        vm.label(rETH, "rETH");
    }
}
