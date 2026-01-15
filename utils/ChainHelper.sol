// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {getConfig} from "./Config.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

error AssetNotFound(string symbol);

struct ChainInfo {
    string name;
    uint256 fromBlockNumber;
}

struct ChainAssets {
    address USDC;
    address USDT;
    address WETH;
}

struct ChainAddressbook {
    ChainInfo chainInfo;
    ChainAssets assets;
}

contract ChainHelper {
    using stdJson for string;

    string public constant CHAINS_CONFIG_SUFFIX = "chains";

    constructor() {
        _labelAddresses(_getAddressBook());
    }

    function _getChainInfo() internal view returns (ChainInfo memory) {
        return _getAddressBook().chainInfo;
    }

    function _getChainName() internal view returns (string memory) {
        return _getAddressBook().chainInfo.name;
    }

    function _getFromBlockNumber() internal view returns (uint256) {
        return _getAddressBook().chainInfo.fromBlockNumber;
    }

    function _getUSDC() internal view returns (address) {
        return _getAddressBook().assets.USDC;
    }

    function _getUSDT() internal view returns (address) {
        return _getAddressBook().assets.USDT;
    }

    function _getWETH() internal view returns (address) {
        return _getAddressBook().assets.WETH;
    }

    /// @notice Get an asset address by symbol (e.g., "DAI", "cbBTC", "rETH")
    /// @param symbol The asset symbol to look up
    /// @return The asset address if it exists on the current chain
    /// @dev Reverts if the asset is not found in the config. Labels the asset for debugging.
    function _getAsset(string memory symbol) internal returns (address) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory configJson = getConfig(CHAINS_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");
        string memory assetPath = string.concat(selectorPrefix, ".assets.", symbol);
        
        address asset = configJson.readAddress(assetPath);
        if (asset == address(0)) {
            revert AssetNotFound(symbol);
        }
        
        // Label the asset for better debugging
        vm.label(asset, symbol);
        
        return asset;
    }

    function _getAddressBook() internal view returns (ChainAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = getConfig(CHAINS_CONFIG_SUFFIX);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        ab.chainInfo.name = configJson.readString(string.concat(selectorPrefix, ".name"));
        ab.chainInfo.fromBlockNumber = configJson.readUint(string.concat(selectorPrefix, ".fromBlockNumber"));

        ab.assets.USDC = configJson.readAddress(string.concat(selectorPrefix, ".assets.USDC"));
        ab.assets.USDT = configJson.readAddress(string.concat(selectorPrefix, ".assets.USDT"));
        ab.assets.WETH = configJson.readAddress(string.concat(selectorPrefix, ".assets.WETH"));
    }

    function _labelAddresses(ChainAddressbook memory ab) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.label(ab.assets.USDC, "USDC");
        vm.label(ab.assets.USDT, "USDT");
        vm.label(ab.assets.WETH, "WETH");
    }
}

