// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestDeployer} from "test/utils/TestDeployer.sol";
import {AssetPriceOracleAndSwapper} from "../../src/mixins/AssetPriceOracleAndSwapper.sol";
import {IAssetPriceOracleAndSwapper} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {UniswapHelper, UniswapAddressbook} from "utils/UniswapHelper.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
import {UniswapV3SwapperEngine} from "src/swapper-engines/UniswapV3SwapperEngine.sol";
import {PriceStrategy, AssetPair} from "src/interfaces/IAssetPriceOracleAndSwapper.sol";

contract AssetPriceOracleAndSwapperTest is TestDeployer, UniswapHelper {
    AssetPriceOracleAndSwapper public assetPriceOracleAndSwapper;
    MockPriceOracle public mockPriceOracle;
    ISwapperEngine public uniswapV3SwapperEngine;

    /// ===== Constants =====

    function setUp() public override {
        super.setUp();

        bytes memory USDC_USDT_V3_POOL_INFO = abi.encodePacked(USDC, uint24(500), USDT);

        assetPriceOracleAndSwapper = new AssetPriceOracleAndSwapper();

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        uniswapV3SwapperEngine = new UniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.quoterV2
        );
        mockPriceOracle = new MockPriceOracle(1e18, USDC, USDT);

        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: USDC_USDT_V3_POOL_INFO,
                priceStrategy: PriceStrategy.OracleOnly,
                swapperAccuracy: 10,
                priceOracle: address(mockPriceOracle)
            })
        );

        // Register rETH to USDC pair using UniswapV3SwapperEngine (multi-hop: rETH -> WETH -> USDC)
        bytes memory rETH_WETH_USDC_V3_POOL_INFO = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee rETH-WETH
            WETH,
            uint24(500), // 0.05% fee WETH-USDC
            USDC
        );
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: rETH_WETH_USDC_V3_POOL_INFO,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_register() public view {
        assertEq(assetPriceOracleAndSwapper.assetPair(USDC, USDT).priceOracle, address(mockPriceOracle));
    }

    function test_swap_uniswap_v3() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(assetPriceOracleAndSwapper), amountOut * 2);

        // Token 0 needs to be first for exact output
        assetPriceOracleAndSwapper.swapForOutput(amountOut, USDC, USDT);

        assertEq(IERC20(USDT).balanceOf(address(assetPriceOracleAndSwapper)), amountOut);
    }

    function test_swap_uniswap_v3_multihop() public {
        uint128 amountOut = 1000e6;
        deal(rETH, address(assetPriceOracleAndSwapper), 1e18);

        // V3 multi-hop path: rETH -> WETH (fee: 100) -> USDC (fee: 500)
        // For EXACT_OUT, path is reversed: output -> fee -> intermediate -> fee -> input
        assetPriceOracleAndSwapper.swapForOutput(amountOut, rETH, USDC);

        assertEq(IERC20(USDC).balanceOf(address(assetPriceOracleAndSwapper)), amountOut);
    }

    function test_RevertWhen_swap_asset_pair_not_registered() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(assetPriceOracleAndSwapper), amountOut * 2);

        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.swapForOutput(amountOut, USDC, address(0));
    }

    function test_getQuote_oracle_only() public view {
        uint256 amountIn = 1000e6;
        uint256 quote = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, USDT);
        assertEq(quote, amountIn);

        uint256 newQuote = assetPriceOracleAndSwapper.getQuote(amountIn, USDT, USDC);
        assertEq(newQuote, amountIn);
    }

    function test_RevertWhen_getQuote_asset_pair_not_registered() public {
        uint256 amountIn = 1000e6;
        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.getQuote(amountIn, USDC, address(0));
    }
}
