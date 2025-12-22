// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {getConfig} from "./Config.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IUniversalRouter} from "@uniswap/universal-router/interfaces/IUniversalRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

struct UniswapAddresses {
    address universalRouter;
    address permit2;
    address quoterV2;
    address quoterV3;
    address v4PositionManager;
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

    function _getPermit2() internal view returns (IPermit2) {
        return IPermit2(_getUniswapAddressBook().uniswapAddresses.permit2);
    }

    function _getQuoterV3() internal view returns (IV4Quoter) {
        return IV4Quoter(_getUniswapAddressBook().uniswapAddresses.quoterV3);
    }

    function _getV4PositionManager() internal view returns (IPositionManager) {
        return IPositionManager(_getUniswapAddressBook().uniswapAddresses.v4PositionManager);
    }

    function _getUniswapAddressBook() internal view returns (UniswapAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = getConfig(UNISWAP_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        ab.uniswapAddresses.universalRouter =
            configJson.readAddress(string.concat(selectorPrefix, ".universalRouter"));
        ab.uniswapAddresses.permit2 =
            configJson.readAddress(string.concat(selectorPrefix, ".permit2"));
        ab.uniswapAddresses.quoterV2 =
            configJson.readAddress(string.concat(selectorPrefix, ".quoterV2"));
        ab.uniswapAddresses.quoterV3 =
            configJson.readAddress(string.concat(selectorPrefix, ".quoterV3"));
        ab.uniswapAddresses.v4PositionManager =
            configJson.readAddress(string.concat(selectorPrefix, ".v4PositionManager"));
    }

    function _labelUniswapAddresses(UniswapAddressbook memory ab) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.label(ab.uniswapAddresses.universalRouter, "Uniswap V4 Universal Router");
        vm.label(ab.uniswapAddresses.permit2, "Permit2");
        vm.label(ab.uniswapAddresses.quoterV2, "Uniswap V3 QuoterV2");
        vm.label(ab.uniswapAddresses.quoterV3, "Uniswap V4 QuoterV3");
    }
}
