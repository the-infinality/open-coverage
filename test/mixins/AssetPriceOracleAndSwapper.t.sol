// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestDeployer} from "../utils/TestDeployer.sol";
import {MockAssetPriceOracleAndSwapper} from "../utils/MockAssetPriceOracleAndSwapper.sol";
import {IAssetPriceOracleAndSwapper} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";
import {UniswapHelper, UniswapAddressbook} from "../../utils/UniswapHelper.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";
import {ISwapperEngine} from "../../src/interfaces/ISwapperEngine.sol";
import {UniswapV3SwapperEngine} from "../../src/swapper-engines/UniswapV3SwapperEngine.sol";
import {PriceStrategy, AssetPair} from "../../src/interfaces/IAssetPriceOracleAndSwapper.sol";

contract AssetPriceOracleAndSwapperTest is TestDeployer, UniswapHelper {
    MockAssetPriceOracleAndSwapper public assetPriceOracleAndSwapper;
    MockPriceOracle public mockPriceOracle;
    ISwapperEngine public uniswapV3SwapperEngine;

    /// ===== Constants =====
    bytes USDC_USDT_V3_POOL_INFO;

    function setUp() public override {
        super.setUp();

        USDC_USDT_V3_POOL_INFO = abi.encodePacked(USDC, uint24(500), USDT);

        assetPriceOracleAndSwapper = new MockAssetPriceOracleAndSwapper(address(this));

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        uniswapV3SwapperEngine = new UniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.viewQuoterV3
        );
        mockPriceOracle = new MockPriceOracle(1, USDC, USDT);

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

    function test_assetPair() public view {
        AssetPair memory pair = assetPriceOracleAndSwapper.assetPair(rETH, USDC);
        assertEq(pair.assetA, rETH);
        assertEq(pair.assetB, USDC);
        assertEq(pair.swapEngine, address(uniswapV3SwapperEngine));
        assertEq(uint16(pair.priceStrategy), uint16(PriceStrategy.SwapperOnly));
        assertEq(pair.swapperAccuracy, 0);

        AssetPair memory pairSwapped = assetPriceOracleAndSwapper.assetPair(USDC, rETH);
        assertEq(pairSwapped.assetA, rETH);
        assertEq(pairSwapped.assetB, USDC);
        assertEq(pairSwapped.swapEngine, address(uniswapV3SwapperEngine));
        assertEq(uint16(pairSwapped.priceStrategy), uint16(PriceStrategy.SwapperOnly));
        assertEq(pairSwapped.swapperAccuracy, 0);
    }

    function test_RevertWhen_register_not_owner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(MockAssetPriceOracleAndSwapper.NotOwner.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: USDC_USDT_V3_POOL_INFO,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    /// @dev Covers branch: priceStrategy == SwapperOnly (priceOracleRequired false) in register
    function test_register_swapperOnly() public {
        address tokenA = makeAddr("tokenA");
        address tokenB = makeAddr("tokenB");
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: tokenA,
                assetB: tokenB,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );

        AssetPair memory pair = assetPriceOracleAndSwapper.assetPair(tokenA, tokenB);
        assertEq(uint16(pair.priceStrategy), uint16(PriceStrategy.SwapperOnly));
        assertEq(pair.priceOracle, address(0));
    }

    function test_RevertWhen_register_PriceOracleRequired() public {
        vm.expectRevert(IAssetPriceOracleAndSwapper.PriceOracleRequired.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: USDC_USDT_V3_POOL_INFO,
                priceStrategy: PriceStrategy.OracleOnly,
                swapperAccuracy: 10,
                priceOracle: address(0)
            })
        );
    }

    function test_RevertWhen_register_InvalidSwapperAccuracy_zeroWhenRequired() public {
        AssetPair memory pair = AssetPair({
            assetA: USDC,
            assetB: USDT,
            swapEngine: address(uniswapV3SwapperEngine),
            poolInfo: USDC_USDT_V3_POOL_INFO,
            priceStrategy: PriceStrategy.OracleOnly,
            swapperAccuracy: 0,
            priceOracle: address(mockPriceOracle)
        });
        // Use low-level call so the reverting branch (priceOracleRequired && swapperAccuracy == 0)
        // is executed and recorded by coverage
        (bool success, bytes memory result) = address(assetPriceOracleAndSwapper)
            .call(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.register.selector, pair));
        assertFalse(success, "register should revert with InvalidSwapperAccuracy");
        assertEq(
            // casting to 'bytes4' is safe because selector are always 4 bytes
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4(result),
            IAssetPriceOracleAndSwapper.InvalidSwapperAccuracy.selector,
            "revert reason should be InvalidSwapperAccuracy"
        );
    }

    /// @dev Also hits revert (priceOracleRequired && swapperAccuracy == 0) via SwapperVerified
    function test_RevertWhen_register_InvalidSwapperAccuracy_zeroWhenRequired_swapperVerified() public {
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);
        MockPriceOracle oracle = new MockPriceOracle(1e18, rETH, USDC);

        vm.expectRevert(IAssetPriceOracleAndSwapper.InvalidSwapperAccuracy.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperVerified,
                swapperAccuracy: 0,
                priceOracle: address(oracle)
            })
        );
    }

    function test_RevertWhen_register_InvalidAssetPair_assetA_zero() public {
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        vm.expectRevert(IAssetPriceOracleAndSwapper.InvalidAssetPair.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: address(0),
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_RevertWhen_register_InvalidAssetPair_assetB_zero() public {
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        vm.expectRevert(IAssetPriceOracleAndSwapper.InvalidAssetPair.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: address(0),
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: poolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_RevertWhen_register_InvalidPoolInfo() public {
        address tokenA = makeAddr("tokenA");
        address tokenB = makeAddr("tokenB");
        // Invalid poolInfo: zero address as first token causes onInit to revert in UniswapV3SwapperEngine
        bytes memory invalidPoolInfo = abi.encodePacked(address(0), USDC);

        vm.expectRevert(IAssetPriceOracleAndSwapper.InvalidPoolInfo.selector);
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: tokenA,
                assetB: tokenB,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: invalidPoolInfo,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 0,
                priceOracle: address(0)
            })
        );
    }

    function test_RevertWhen_swapForInput_swapFailed() public {
        // Use an amountIn so large that the swap fails (e.g. exceeds liquidity), triggering SwapFailed
        uint256 amountIn = 1000e6 * 1e12; // 1e21 raw units
        deal(USDT, address(assetPriceOracleAndSwapper), amountIn);

        vm.expectRevert(IAssetPriceOracleAndSwapper.SwapFailed.selector);
        assetPriceOracleAndSwapper.swapForInput(amountIn, USDC, USDT);
    }

    function test_swapForOutput() public {
        uint128 amountOut = 1000e6;
        // Deal USDT (swap/input asset) instead of USDC
        deal(USDT, address(assetPriceOracleAndSwapper), amountOut * 2);

        // Swap from USDT (swap) to get amountOut of USDC (base)
        assetPriceOracleAndSwapper.swapForOutput(amountOut, USDC, USDT);

        assertEq(IERC20(USDC).balanceOf(address(assetPriceOracleAndSwapper)), amountOut);
    }

    function test_swapForInput() public {
        uint128 amountIn = 1000e6;
        // Deal USDT (swap/input asset) instead of USDC
        deal(USDT, address(assetPriceOracleAndSwapper), amountIn * 2);

        // Swap from USDT (swap) to get amountOut of USDC (base)
        assetPriceOracleAndSwapper.swapForInput(amountIn, USDC, USDT);
    }

    function test_RevertWhen_swapForOutput_slippageTooLow() public {
        assetPriceOracleAndSwapper.setSwapSlippage(0);

        uint128 amountOut = 1000e6;
        // Deal USDT (swap/input asset) instead of USDC
        deal(USDT, address(assetPriceOracleAndSwapper), amountOut * 2);

        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.SwapFailed.selector));
        assetPriceOracleAndSwapper.swapForOutput(amountOut, USDC, USDT);
    }

    function test_RevertWhen_swapForOutput_slippageTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.InvalidSwapSlippage.selector));
        assetPriceOracleAndSwapper.setSwapSlippage(10001);
    }

    function test_swapForOutputQuote() public view {
        uint128 amountOut = 1000e6;

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // Get the base quote from swapper from oracle
        uint256 baseQuote = mockPriceOracle.getQuote(amountOut, USDC, USDT);

        // Get quote with slippage
        (uint256 maxAmountIn,) = assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, USDC, USDT);

        // Verify slippage is added: maxAmountIn = baseQuote + (slippage * baseQuote) / 10000
        uint256 expectedMaxAmountIn = baseQuote + (uint256(slippage) * baseQuote) / 10000;
        assertEq(maxAmountIn, expectedMaxAmountIn);
        assertGt(maxAmountIn, baseQuote);
    }

    function test_swapForOutputQuote_SwapperOnly() public {
        // Re-register as swapper only
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: USDC_USDT_V3_POOL_INFO,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 10,
                priceOracle: address(mockPriceOracle)
            })
        );

        uint128 amountOut = 1000e6;

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // swapForOutputQuote(amountOut, USDC, USDT) = max USDT to spend for amountOut USDC → getQuote(amountOut, USDT, USDC)
        (uint256 baseQuote,) = assetPriceOracleAndSwapper.getQuote(amountOut, USDT, USDC);

        // Get quote with slippage
        (uint256 maxAmountIn,) = assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, USDC, USDT);

        // Verify slippage is added: maxAmountIn = baseQuote + (slippage * baseQuote) / 10000
        uint256 expectedMaxAmountIn = baseQuote + (uint256(slippage) * baseQuote) / 10000;
        assertEq(maxAmountIn, expectedMaxAmountIn);
        assertGt(maxAmountIn, baseQuote);
    }

    function test_swapForOutputQuote_withCustomSlippage() public {
        // Set slippage to 0.5% (50 basis points)
        assetPriceOracleAndSwapper.setSwapSlippage(50);

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        uint128 amountOut = 1000e6;

        // Get the base quote from swapper from oracle
        uint256 baseQuote = mockPriceOracle.getQuote(amountOut, USDC, USDT);

        // Get quote with slippage
        (uint256 maxAmountIn,) = assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, USDC, USDT);

        // Verify slippage is added: maxAmountIn = baseQuote + (slippage * baseQuote) / 10000
        uint256 expectedMaxAmountIn = baseQuote + (uint256(slippage) * baseQuote) / 10000;
        assertEq(maxAmountIn, expectedMaxAmountIn);
        assertGt(maxAmountIn, baseQuote);
    }

    /// @dev By default we test for the oracle only quote stategy
    function test_swapForInputQuote() public view {
        uint128 amountIn = 1000e6;

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // Get the base quote from oracle
        uint256 baseQuote = mockPriceOracle.getQuote(amountIn, USDC, USDT);

        // Get quote with slippage
        (uint256 minAmountOut,) = assetPriceOracleAndSwapper.swapForInputQuote(amountIn, USDC, USDT);

        // Verify slippage is subtracted: minAmountOut = baseQuote - (slippage * baseQuote) / 10000
        uint256 expectedMinAmountOut = baseQuote - (uint256(slippage) * baseQuote) / 10000;
        assertEq(minAmountOut, expectedMinAmountOut);
        assertLe(minAmountOut, baseQuote);
    }

    function test_swapForInputQuote_SwapperOnly() public {
        // Re-register as swapper only
        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: USDC,
                assetB: USDT,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: USDC_USDT_V3_POOL_INFO,
                priceStrategy: PriceStrategy.SwapperOnly,
                swapperAccuracy: 10,
                priceOracle: address(mockPriceOracle)
            })
        );

        uint128 amountIn = 1000e6;

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // Get the base quote from swapper using the registered asset pair's pool info
        AssetPair memory pair = assetPriceOracleAndSwapper.assetPair(USDC, USDT);
        uint256 baseQuote = uniswapV3SwapperEngine.getQuote(pair.poolInfo, amountIn, USDC, USDT);

        // Get quote with slippage
        (uint256 minAmountOut,) = assetPriceOracleAndSwapper.swapForInputQuote(amountIn, USDC, USDT);

        // Verify slippage is subtracted: minAmountOut = baseQuote - (slippage * baseQuote) / 10000
        uint256 expectedMinAmountOut = baseQuote - (uint256(slippage) * baseQuote) / 10000;
        assertEq(minAmountOut, expectedMinAmountOut);
        assertLe(minAmountOut, baseQuote);
    }

    function test_swapForInputQuote_withCustomSlippage() public {
        // Set slippage to 0.5% (50 basis points)
        assetPriceOracleAndSwapper.setSwapSlippage(50);

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        uint128 amountIn = 1000e6;

        // Get the base quote from oracle
        uint256 baseQuote = mockPriceOracle.getQuote(amountIn, USDC, USDT);

        // Get quote with slippage
        (uint256 minAmountOut,) = assetPriceOracleAndSwapper.swapForInputQuote(amountIn, USDC, USDT);

        // Verify slippage is subtracted: minAmountOut = baseQuote - (slippage * baseQuote) / 10000
        uint256 expectedMinAmountOut = baseQuote - (uint256(slippage) * baseQuote) / 10000;
        assertEq(minAmountOut, expectedMinAmountOut);
        assertLt(minAmountOut, baseQuote);
    }

    function test_swapForOutputQuote_multihop_USDC_to_rETH() public view {
        uint128 amountOut = 1e18; // 1 rETH

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // swapForOutputQuote(amountOut, rETH, USDC) = max USDC to spend for amountOut rETH → getQuote(amountOut, USDC, rETH)
        (uint256 baseQuote,) = assetPriceOracleAndSwapper.getQuote(amountOut, USDC, rETH);

        // Get quote with slippage
        (uint256 maxAmountIn,) = assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, rETH, USDC);

        // Verify slippage is added: maxAmountIn = baseQuote + (slippage * baseQuote) / 10000
        uint256 expectedMaxAmountIn = baseQuote + (uint256(slippage) * baseQuote) / 10000;
        assertEq(maxAmountIn, expectedMaxAmountIn);
        assertGt(maxAmountIn, baseQuote);
    }

    function test_swapForOutputQuote_multihop_rETH_to_USDC() public view {
        uint128 amountOut = 10e18; // 10e18 USDC (output); max rETH (input) to spend

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // swapForOutputQuote(amountOut, USDC, rETH) = max rETH to spend for amountOut USDC → getQuote(amountOut, rETH, USDC)
        (uint256 baseQuote,) = assetPriceOracleAndSwapper.getQuote(amountOut, rETH, USDC);

        // Get quote with slippage
        (uint256 maxAmountIn,) = assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, USDC, rETH);

        // Verify slippage is added: maxAmountIn = baseQuote + (slippage * baseQuote) / 10000
        uint256 expectedMaxAmountIn = baseQuote + (uint256(slippage) * baseQuote) / 10000;
        assertEq(maxAmountIn, expectedMaxAmountIn);
        assertGt(maxAmountIn, baseQuote);
    }

    function test_swapForInputQuote_multihop() public view {
        uint128 amountIn = 10000e6; // 10000 USDC

        // Get the base quote from swapper using the registered asset pair's pool info
        AssetPair memory pair = assetPriceOracleAndSwapper.assetPair(rETH, USDC);
        uint256 baseQuote = uniswapV3SwapperEngine.getQuote(pair.poolInfo, amountIn, USDC, rETH);

        // Get the current slippage value
        uint16 slippage = assetPriceOracleAndSwapper.swapSlippage();

        // Get quote with slippage
        (uint256 minAmountOut,) = assetPriceOracleAndSwapper.swapForInputQuote(amountIn, USDC, rETH);

        // Verify slippage is subtracted: minAmountOut = baseQuote - (slippage * baseQuote) / 10000
        uint256 expectedMinAmountOut = baseQuote - (uint256(slippage) * baseQuote) / 10000;
        assertEq(minAmountOut, expectedMinAmountOut);
        assertLe(minAmountOut, baseQuote); // Use <= because small values may round to 0 slippage
    }

    function test_RevertWhen_swapForOutputQuote_asset_pair_not_registered() public {
        uint128 amountOut = 1000e6;
        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.swapForOutputQuote(amountOut, USDC, address(0));
    }

    function test_RevertWhen_swapForInputQuote_asset_pair_not_registered() public {
        uint128 amountIn = 1000e6;
        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.swapForInputQuote(amountIn, USDC, address(0));
    }

    function test_swap_uniswap_v3_multihop() public {
        uint128 amountOut = 1e18; // 1 rETH (base is output)
        // Deal USDC (swap/input asset) instead of rETH
        deal(USDC, address(assetPriceOracleAndSwapper), 10000e6);

        // V3 multi-hop path: rETH -> WETH (fee: 100) -> USDC (fee: 500)
        // For EXACT_OUT, path format: output -> fee -> intermediate -> fee -> input
        // Swap from USDC (swap) to get amountOut of rETH (base)
        assetPriceOracleAndSwapper.swapForOutput(amountOut, rETH, USDC);

        assertEq(IERC20(rETH).balanceOf(address(assetPriceOracleAndSwapper)), amountOut);
    }

    function test_RevertWhen_swap_asset_pair_not_registered() public {
        uint128 amountOut = 1000e6;
        deal(USDT, address(assetPriceOracleAndSwapper), amountOut * 2);

        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.swapForOutput(amountOut, USDC, address(0));
    }

    function test_getQuote_oracle_only() public view {
        uint256 amountIn = 1000e6;
        (uint256 quote, bool verified) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, USDT);
        assertEq(quote, mockPriceOracle.getQuote(amountIn, USDC, USDT));
        assertEq(verified, true);
        // MockPriceOracle returns amountIn, so verification depends on swapper quote matching
        // Since swapperAccuracy is 10 (0.1%), verification may pass if within tolerance

        (uint256 quote2, bool verified2) = assetPriceOracleAndSwapper.getQuote(amountIn, USDT, USDC);
        assertGt(quote2, 0);
        assertEq(verified2, true);
    }

    function test_getQuote_swapper_only() public view {
        uint256 amountIn = 1e18;
        (uint256 quote, bool verified) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, rETH);

        assertEq(verified, true); // No oracle to verify against
        assertGt(quote, 1000e6);
    }

    function test_getQuote_swapper_only_reverse() public view {
        uint256 amountIn = 1000e6; // 1000 USDC
        (uint256 quote, bool verified) = assetPriceOracleAndSwapper.getQuote(amountIn, rETH, USDC);

        assertEq(verified, true); // No oracle to verify against
        assertGt(quote, 1e17);
    }

    function test_getQuote_swapper_verified() public {
        // Get the pool info from the existing registered asset pair
        AssetPair memory existingPair = assetPriceOracleAndSwapper.assetPair(rETH, USDC);
        bytes memory rETH_WETH_USDC_V3_POOL_INFO = existingPair.poolInfo;

        uint256 swapperQuote = uniswapV3SwapperEngine.getQuote(rETH_WETH_USDC_V3_POOL_INFO, 1e6, rETH, USDC);
        swapperQuote = swapperQuote / 1e6;
        MockPriceOracle newMockPriceOracle = new MockPriceOracle(swapperQuote - (swapperQuote / 100), rETH, USDC);

        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: rETH_WETH_USDC_V3_POOL_INFO,
                priceStrategy: PriceStrategy.SwapperVerified,
                swapperAccuracy: 500, // 5% tolerance
                priceOracle: address(newMockPriceOracle)
            })
        );

        uint256 swapperQuoteToVerify = uniswapV3SwapperEngine.getQuote(rETH_WETH_USDC_V3_POOL_INFO, 1e18, USDC, rETH);

        uint256 amountIn = 1e18;
        (uint256 quote, bool verified) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, rETH);

        assertEq(verified, true); // No oracle to verify against
        assertEq(quote, swapperQuoteToVerify);

        newMockPriceOracle.setMultiplier(swapperQuote - (swapperQuote * 10 / 100));
        (uint256 quote2, bool verified2) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, rETH);
        assertEq(verified2, false);
        assertEq(quote2, swapperQuoteToVerify);
    }

    function test_getQuote_oracle_verified() public {
        uint256 amountIn = 1e18;

        // Get the pool info from the existing registered asset pair
        AssetPair memory existingPair = assetPriceOracleAndSwapper.assetPair(rETH, USDC);
        bytes memory rETH_WETH_USDC_V3_POOL_INFO = existingPair.poolInfo;

        // Manually get the swapper quote to know what the swapper will return
        uint256 swapperQuote = uniswapV3SwapperEngine.getQuote(rETH_WETH_USDC_V3_POOL_INFO, 1e6, rETH, USDC);
        swapperQuote = swapperQuote / 1e6;
        MockPriceOracle newMockPriceOracle = new MockPriceOracle(swapperQuote - (swapperQuote / 100), rETH, USDC);

        assetPriceOracleAndSwapper.register(
            AssetPair({
                assetA: rETH,
                assetB: USDC,
                swapEngine: address(uniswapV3SwapperEngine),
                poolInfo: rETH_WETH_USDC_V3_POOL_INFO,
                priceStrategy: PriceStrategy.OracleVerified,
                swapperAccuracy: 500, // 5% tolerance
                priceOracle: address(newMockPriceOracle)
            })
        );

        // Get quote - should return oracle quote and be verified
        (uint256 quote, bool verified) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, rETH);

        // Manually verify the oracle quote matches what we expect
        uint256 expectedOracleQuote = newMockPriceOracle.getQuote(amountIn, USDC, rETH);
        assertEq(quote, expectedOracleQuote); // Quote should come from oracle
        assertEq(verified, true); // Should be verified since oracle quote matches swapper within tolerance
        assertGt(quote, 1000e6);

        // Change oracle to return a value outside tolerance (10% difference)
        uint256 newMultiplier = swapperQuote + (swapperQuote * 10 / 100); // 10% higher
        newMockPriceOracle.setMultiplier(newMultiplier);

        (uint256 quote2, bool verified2) = assetPriceOracleAndSwapper.getQuote(amountIn, USDC, rETH);

        // Manually verify the new oracle quote
        uint256 expectedOracleQuote2 = newMockPriceOracle.getQuote(amountIn, USDC, rETH);
        assertEq(quote2, expectedOracleQuote2); // Quote should still come from oracle
        assertEq(verified2, false); // Should fail verification since oracle quote is outside tolerance
        assertGt(quote2, 1000e6);
    }

    function test_RevertWhen_getQuote_asset_pair_not_registered() public {
        uint256 amountIn = 1000e6;
        vm.expectRevert(abi.encodeWithSelector(IAssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        assetPriceOracleAndSwapper.getQuote(amountIn, USDC, address(0));
    }
}
