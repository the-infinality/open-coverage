// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {getConfig} from "./Config.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";

struct UniswapAddresses {
    address universalRouter;
    address permit2;
}

struct UniswapAddressbook {
    UniswapAddresses uniswapAddresses;
}


contract UniswapHelper {
    using stdJson for string;

    string public constant UNISWAP_CONFIG_SUFFIX = "uniswap";

    constructor() {
        _labelUniswapAddresses(_getUniswapAddressBook());
    }

    function _getUniversalRouter() internal view returns (IUniversalRouter) {
        return IUniversalRouter(_getUniswapAddressBook().uniswapAddresses.universalRouter);
    }

    function _getUniswapAddressBook() internal view returns (UniswapAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = getConfig(UNISWAP_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        ab.uniswapAddresses.universalRouter =
            configJson.readAddress(string.concat(selectorPrefix, ".universalRouter"));
        ab.uniswapAddresses.permit2 =
            configJson.readAddress(string.concat(selectorPrefix, ".permit2"));
    }

    function _labelUniswapAddresses(UniswapAddressbook memory ab) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.label(ab.uniswapAddresses.universalRouter, "Uniswap V4 Universal Router");
        vm.label(ab.uniswapAddresses.permit2, "Permit2");
    }
}
