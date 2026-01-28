// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UniswapHelper, UniswapAddressbook} from "../utils/UniswapHelper.sol";
import {UniswapV3SwapperEngine} from "../src/swapper-engines/UniswapV3SwapperEngine.sol";

/// @title DeployUniswapV3SwapperEngine
/// @notice Script to deploy UniswapV3SwapperEngine
/// @dev Uses UniswapHelper to get chain-specific addresses from config
contract DeployUniswapV3SwapperEngine is Script, UniswapHelper {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";

    function run() public returns (address swapperEngineAddress) {
        vm.startBroadcast();

        console.log("Deploying UniswapV3SwapperEngine...");
        console.log("Chain ID:", block.chainid);

        // Get Uniswap addresses from config
        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        address universalRouter = uniswapAddressBook.uniswapAddresses.universalRouter;
        address permit2 = uniswapAddressBook.uniswapAddresses.permit2;
        address quoter = uniswapAddressBook.uniswapAddresses.viewQuoterV3;

        console.log("Universal Router:", universalRouter);
        console.log("Permit2:", permit2);
        console.log("Quoter (V3 View Quoter):", quoter);

        // Deploy UniswapV3SwapperEngine
        UniswapV3SwapperEngine swapperEngine = new UniswapV3SwapperEngine(universalRouter, permit2, quoter);
        swapperEngineAddress = address(swapperEngine);

        vm.stopBroadcast();

        _logDeploymentSummary(swapperEngineAddress);

        // Only save deployed address when actually broadcasting
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _saveDeployment(swapperEngineAddress);
            console.log("Deployment saved to:", DEPLOYMENTS_PATH);
        } else {
            console.log("Dry run - skipping deployment file update");
        }

        return swapperEngineAddress;
    }

    function _logDeploymentSummary(address swapperEngineAddress) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("UniswapV3SwapperEngine deployed at:", swapperEngineAddress);
        console.log("Chain ID:", block.chainid);
        console.log("\nNote: Register this swapper engine with your CoverageAgent using:");
        console.log("  setSwapperEngine(bytes32 engineId, address swapperEngine)");
    }

    function _saveDeployment(address swapperEngineAddress) internal {
        // Build the JSON path for this chain's deployment
        string memory chainId = vm.toString(block.chainid);
        string memory jsonPath = string.concat(".", chainId, ".UniswapV3SwapperEngine");

        // Write the address to the deployments file
        vm.writeJson(vm.toString(swapperEngineAddress), DEPLOYMENTS_PATH, jsonPath);

        console.log("\nSaved deployment to deployments.json:");
        console.log("  Chain ID:", chainId);
        console.log("  Key: UniswapV3SwapperEngine");
        console.log("  Address:", swapperEngineAddress);
    }
}

