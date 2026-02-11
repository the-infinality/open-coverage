// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UniswapHelper, UniswapAddressbook} from "../utils/UniswapHelper.sol";
import {UniswapV3SwapperEngine} from "../src/swapper-engines/UniswapV3SwapperEngine.sol";
import {DeploymentUtils} from "../utils/deployments/DeploymentUtils.sol";

/// @title DeployUniswapV3SwapperEngine
/// @notice Script to deploy UniswapV3SwapperEngine
/// @dev Uses UniswapHelper to get chain-specific addresses from config. If a deployment already exists for the chain, prompts to type 'y' to override.
contract DeployUniswapV3SwapperEngine is Script, UniswapHelper {
    string constant DEPLOYMENTS_PATH = "config/deployments.json";
    string constant UNISWAP_V3_SWAPPER_ENGINE = "UniswapV3SwapperEngine";

    function run() public returns (address swapperEngineAddress) {
        _requireOverrideIfExistingDeployment();

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

    function _requireOverrideIfExistingDeployment() internal {
        try vm.readFile(DEPLOYMENTS_PATH) returns (string memory json) {
            string memory chainId = vm.toString(block.chainid);
            string memory chainPath = string.concat(".", chainId);
            try vm.parseJsonKeys(json, chainPath) returns (string[] memory keys) {
                bool exists;
                for (uint256 k = 0; k < keys.length; k++) {
                    if (keccak256(abi.encodePacked(keys[k])) == keccak256(abi.encodePacked(UNISWAP_V3_SWAPPER_ENGINE)))
                    {
                        exists = true;
                        break;
                    }
                }
                if (!exists) return;
                address existingAddr =
                    vm.parseJsonAddress(json, string.concat(chainPath, ".", UNISWAP_V3_SWAPPER_ENGINE));
                bytes memory onChain = existingAddr.code;
                bytes memory compiled =
                    vm.getDeployedCode("src/swapper-engines/UniswapV3SwapperEngine.sol:UniswapV3SwapperEngine");
                bool bytecodeSame =
                    onChain.length > 0 && compiled.length > 0 && DeploymentUtils.bytecodeMatches(onChain, compiled);
                if (bytecodeSame) {
                    string memory input = vm.prompt(
                        string.concat(
                            "UniswapV3SwapperEngine deployment already exists for chain ",
                            chainId,
                            ".\n",
                            "Bytecode is identical. Recommended to use the existing contract.\n",
                            "Type 'y' to deploy anyway (override): "
                        )
                    );
                    require(
                        keccak256(abi.encodePacked(input)) == keccak256(abi.encodePacked("y")),
                        "Deployment cancelled (expected 'y' to override)"
                    );
                } else {
                    string memory input = vm.prompt(
                        string.concat(
                            "UniswapV3SwapperEngine deployment already exists for chain ",
                            chainId,
                            ".\n",
                            "Type 'y' to override existing deployment and continue: "
                        )
                    );
                    require(
                        keccak256(abi.encodePacked(input)) == keccak256(abi.encodePacked("y")),
                        "Deployment cancelled (expected 'y' to override)"
                    );
                }
            } catch {}
        } catch {}
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

