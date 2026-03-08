// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {getConfig} from "../../utils/Config.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployerHelperScript} from "../../utils/deployments/DeployerHelperScript.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {EigenCoverageDiamond} from "../../src/providers/eigenlayer/EigenCoverageDiamond.sol";
import {IEigenServiceManager} from "../../src/providers/eigenlayer/interfaces/IEigenServiceManager.sol";
import {ExampleCoverageAgent} from "../../src/ExampleCoverageAgent.sol";
import {
    IAssetPriceOracleAndSwapper,
    AssetPair,
    PriceStrategy
} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";

struct DeployToTestnetResult {
    address diamondCut;
    address diamondLoupe;
    address ownership;
    address eigenServiceManager;
    address eigenCoverageProvider;
    address assetPriceOracleAndSwapper;
    address swapperEngine;
    address eigenCoverageDiamond;
    address exampleCoverageAgent;
}

string constant CHAINS_CONFIG_SUFFIX = "chains";
string constant EXAMPLE_COVERAGE_AGENT = "ExampleCoverageAgent";

/// @title DeployTestnet
/// @notice Orchestrates full testnet deployment: facets, UniswapV3SwapperEngine, EigenCoverageDiamond,
///         USDC/WETH asset pair registration, ExampleCoverageAgent; registers the agent with the diamond; updates config.
contract DeployTestnet is DeployerHelperScript {
    using stdJson for string;

    function run() public returns (address eigenCoverageDiamondAddress) {
        vm.startBroadcast();

        DeployToTestnetResult memory r;

        console.log("[1/11] Deploying diamond facets (DiamondCut, DiamondLoupe, Ownership)...");
        (r.diamondCut, r.diamondLoupe, r.ownership) = _deployDiamondFacets();
        console.log("      DiamondCutFacet:", r.diamondCut);
        console.log("      DiamondLoupeFacet:", r.diamondLoupe);
        console.log("      OwnershipFacet:", r.ownership);

        console.log("[2/11] Deploying Eigen provider facets...");
        (r.eigenServiceManager, r.eigenCoverageProvider) = _deployEigenProviderFacets();
        console.log("      EigenServiceManagerFacet:", r.eigenServiceManager);
        console.log("      EigenCoverageProviderFacet:", r.eigenCoverageProvider);

        console.log("[3/11] Deploying AssetPriceOracleAndSwapper facet...");
        r.assetPriceOracleAndSwapper = _deployAssetPriceOracleAndSwapperFacet();
        console.log("      AssetPriceOracleAndSwapperFacet:", r.assetPriceOracleAndSwapper);

        console.log("[4/11] Deploying UniswapV3SwapperEngine...");
        UniswapAddressbook memory uniswapBook = _getUniswapAddressBook();
        r.swapperEngine = _deployUniswapV3SwapperEngine(
            uniswapBook.uniswapAddresses.universalRouter,
            uniswapBook.uniswapAddresses.permit2,
            uniswapBook.uniswapAddresses.viewQuoterV3
        );
        console.log("      UniswapV3SwapperEngine:", r.swapperEngine);

        console.log("[5/11] Building facet cuts and deploying EigenCoverageDiamond...");
        string memory metadataURI = vm.envOr("AVS_METADATA_URI", string("https://coverage.example.com/metadata.json"));
        IDiamondCut.FacetCut[] memory cuts = _buildAllFacetCuts(
            r.diamondCut,
            r.diamondLoupe,
            r.ownership,
            r.eigenServiceManager,
            r.eigenCoverageProvider,
            r.assetPriceOracleAndSwapper
        );
        EigenCoverageDiamond.DiamondArgs memory args = _buildDiamondArgs(msg.sender, metadataURI);
        r.eigenCoverageDiamond = _deployEigenCoverageDiamond(cuts, args);
        eigenCoverageDiamondAddress = r.eigenCoverageDiamond;
        console.log("      EigenCoverageDiamond:", r.eigenCoverageDiamond);

        console.log("[6/11] Whitelisting WETH strategy on EigenCoverageDiamond...");
        address wethStrategy = address(_getWethStrategy());
        IEigenServiceManager(r.eigenCoverageDiamond).setStrategyWhitelist(wethStrategy, true);
        console.log("      WETH strategy whitelisted:", wethStrategy);

        console.log("[7/11] Registering USDC/WETH asset pair on EigenCoverageDiamond...");
        (address usdc, address weth) = _getUsdcAndWeth();
        bytes memory poolInfo = _getUsdcWethPoolInfo();
        IAssetPriceOracleAndSwapper(r.eigenCoverageDiamond)
            .register(
                AssetPair({
                    assetA: usdc,
                    assetB: weth,
                    swapEngine: r.swapperEngine,
                    poolInfo: poolInfo,
                    priceStrategy: PriceStrategy.SwapperOnly,
                    swapperAccuracy: 0,
                    priceOracle: address(0)
                })
            );
        console.log("      Registered USDC/WETH pair. USDC:", usdc, "WETH:", weth);
        console.log("      poolInfo length:", poolInfo.length);

        console.log("[8/11] Deploying ExampleCoverageAgent...");
        address coverageAsset = _getCoverageAsset();
        string memory agentMetadataURI =
            vm.envOr("COVERAGE_AGENT_METADATA_URI", string("https://coverage.example.com/agent-metadata.json"));
        ExampleCoverageAgent agent = new ExampleCoverageAgent(msg.sender, coverageAsset, agentMetadataURI);
        r.exampleCoverageAgent = address(agent);
        console.log("      ExampleCoverageAgent:", r.exampleCoverageAgent);
        console.log("      Coordinator:", msg.sender);
        console.log("      Coverage asset:", coverageAsset);

        console.log("[9/11] Registering ExampleCoverageAgent with EigenCoverageDiamond...");
        agent.registerCoverageProvider(r.eigenCoverageDiamond);
        console.log("      Registered agent", r.exampleCoverageAgent, "with diamond", r.eigenCoverageDiamond);

        vm.stopBroadcast();

        console.log("[10/11] Saving deployments to config...");
        _saveDeploymentsToConfig(r);

        console.log("[11/11] Done.");
        _logDeploymentSummary(r);

        return eigenCoverageDiamondAddress;
    }

    function _getCoverageAsset() internal view returns (address) {
        address fromEnv = vm.envOr("COVERAGE_ASSET", address(0));
        if (fromEnv != address(0)) return fromEnv;
        (, address weth) = _getUsdcAndWeth();
        return weth;
    }

    function _getUsdcAndWeth() internal view returns (address usdc, address weth) {
        string memory configJson = getConfig(CHAINS_CONFIG_SUFFIX);
        string memory chainKey = string.concat("$['", vm.toString(block.chainid), "']");
        usdc = configJson.readAddress(string.concat(chainKey, ".assets.USDC"));
        weth = configJson.readAddress(string.concat(chainKey, ".assets.WETH"));
    }

    /// @dev Reads USDC/WETH poolInfo from config/uniswap.json for current chain (poolPaths["v3"]["USDC/WETH"].poolInfo).
    function _getUsdcWethPoolInfo() internal view returns (bytes memory) {
        string memory configJson = getConfig(UNISWAP_CONFIG_SUFFIX);
        string memory chainId = vm.toString(block.chainid);
        string memory key = string.concat("$['", chainId, "']['poolPaths']['v3']['USDC/WETH']['poolInfo']");
        try vm.parseJsonBytes(configJson, key) returns (bytes memory data) {
            if (data.length > 0) return data;
        } catch {}
        try vm.parseJsonString(configJson, key) returns (string memory hexStr) {
            bytes memory b = _hexStringToBytes(hexStr);
            if (b.length > 0) return b;
        } catch {}
        revert(
            string.concat(
                "DeployTestnet: no poolPaths.v3.USDC/WETH.poolInfo in config/uniswap.json for chain ", chainId
            )
        );
    }

    function _hexStringToBytes(string memory hexStr) internal pure returns (bytes memory) {
        bytes memory s = bytes(hexStr);
        uint256 start = 0;
        if (s.length >= 2 && s[0] == "0" && (s[1] == "x" || s[1] == "X")) start = 2;
        uint256 len = s.length - start;
        if (len == 0) return "";
        if (len % 2 != 0) {
            bytes memory padded = new bytes(len + 1);
            padded[0] = "0";
            for (uint256 i = 0; i < len; i++) {
                padded[i + 1] = s[start + i];
            }
            return _hexToBytesFromBytes(padded, 0);
        }
        return _hexToBytesFromBytes(s, start);
    }

    function _hexToBytesFromBytes(bytes memory s, uint256 start) internal pure returns (bytes memory) {
        uint256 len = s.length - start;
        if (len % 2 != 0) return "";
        uint256 outLen = len / 2;
        bytes memory out = new bytes(outLen);
        for (uint256 i = 0; i < outLen; i++) {
            uint256 hi = _hexCharToNibble(s[start + i * 2]);
            uint256 lo = _hexCharToNibble(s[start + i * 2 + 1]);
            if (hi > 15 || lo > 15) return "";
            out[i] = bytes1(uint8(hi * 16 + lo));
        }
        return out;
    }

    function _hexCharToNibble(bytes1 c) internal pure returns (uint256) {
        if (c >= 0x30 && c <= 0x39) return uint8(c) - 0x30;
        if (c >= 0x41 && c <= 0x46) return uint8(c) - 0x41 + 10;
        if (c >= 0x61 && c <= 0x66) return uint8(c) - 0x61 + 10;
        return 255;
    }

    function _saveDeploymentsToConfig(DeployToTestnetResult memory r) internal {
        string[] memory names = new string[](9);
        address[] memory addrs = new address[](9);
        names[0] = DIAMOND_CUT_FACET;
        addrs[0] = r.diamondCut;
        names[1] = DIAMOND_LOUPE_FACET;
        addrs[1] = r.diamondLoupe;
        names[2] = OWNERSHIP_FACET;
        addrs[2] = r.ownership;
        names[3] = EIGEN_SERVICE_MANAGER_FACET;
        addrs[3] = r.eigenServiceManager;
        names[4] = EIGEN_COVERAGE_PROVIDER_FACET;
        addrs[4] = r.eigenCoverageProvider;
        names[5] = ASSET_PRICE_ORACLE_AND_SWAPPER_FACET;
        addrs[5] = r.assetPriceOracleAndSwapper;
        names[6] = UNISWAP_V3_SWAPPER_ENGINE;
        addrs[6] = r.swapperEngine;
        names[7] = EIGEN_COVERAGE_DIAMOND;
        addrs[7] = r.eigenCoverageDiamond;
        names[8] = EXAMPLE_COVERAGE_AGENT;
        addrs[8] = r.exampleCoverageAgent;
        _saveIfBroadcasting(names, addrs);
    }

    function _logDeploymentSummary(DeployToTestnetResult memory r) internal view {
        console.log("\n=== Deploy to Testnet - Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log(DIAMOND_CUT_FACET, r.diamondCut);
        console.log(DIAMOND_LOUPE_FACET, r.diamondLoupe);
        console.log(OWNERSHIP_FACET, r.ownership);
        console.log(EIGEN_SERVICE_MANAGER_FACET, r.eigenServiceManager);
        console.log(EIGEN_COVERAGE_PROVIDER_FACET, r.eigenCoverageProvider);
        console.log(ASSET_PRICE_ORACLE_AND_SWAPPER_FACET, r.assetPriceOracleAndSwapper);
        console.log(UNISWAP_V3_SWAPPER_ENGINE, r.swapperEngine);
        console.log(EIGEN_COVERAGE_DIAMOND, r.eigenCoverageDiamond);
        console.log(EXAMPLE_COVERAGE_AGENT, r.exampleCoverageAgent);
        console.log("==============================================\n");
    }
}
