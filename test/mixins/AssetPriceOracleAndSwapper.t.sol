// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestDeployer} from "test/utils/TestDeployer.sol";
import {
    AssetPriceOracleAndSwapper,
    SwapEngine,
    SwapParams,
    UniswapV4PoolInfo
} from "../../src/mixins/AssetPriceOracleAndSwapper.sol";
import {UniswapHelper, UniswapAddressbook} from "utils/UniswapHelper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {MockPriceOracle} from "../utils/MockPriceOracle.sol";

contract MockContract is AssetPriceOracleAndSwapper, Initializable {
    constructor() {}

    function initialize(address universalRouter_, address permit2_) public initializer {
        __AssetPriceOracleAndSwapper_init(universalRouter_, permit2_);
    }
}

contract AssetPriceOracleAndSwapperTest is TestDeployer, UniswapHelper {
    MockContract public mockContract;
    MockPriceOracle public mockPriceOracle;

    /// ===== Constants =====
    bytes32 public USDC_USDT_POOL_PATH;
    bytes public USDC_USDT_V4_POOL_INFO;

    function setUp() public override {
        super.setUp();

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        mockContract = new MockContract();
        mockContract.initialize(
            uniswapAddressBook.uniswapAddresses.universalRouter, uniswapAddressBook.uniswapAddresses.permit2
        );
        mockPriceOracle = new MockPriceOracle(1e18, USDC, USDT);

        // Add V4 pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(USDT),
            fee: 100,
            tickSpacing: 1,
            hooks: IHooks(address(0))
        });

        UniswapV4PoolInfo memory uniswapV4PoolInfo = UniswapV4PoolInfo({poolKey: poolKey, zeroForOne: true});

        SwapParams memory swapParams =
            SwapParams({swapEngine: SwapEngine.UNISWAP_V4_SINGLE_HOP, poolInfo: abi.encode(uniswapV4PoolInfo)});
        mockContract.registerPriceAdaptor(address(mockPriceOracle), USDC, USDT, swapParams);
    }

    function test_registerPriceAdaptor() public view {
        assertEq(mockContract.assetPair(USDC, USDT).priceOracle, address(mockPriceOracle));
    }

    function test_swap_uniswap_v4() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(mockContract), amountOut * 2);

        mockContract.swap(amountOut, USDC, USDT);

        assertEq(IERC20(USDT).balanceOf(address(mockContract)), amountOut);
    }

    function test_swap_uniswap_v3() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(mockContract), amountOut * 2);

        // Token 0 needs to be first for exact output
        bytes memory poolInfo = abi.encodePacked(
            USDT, // 20 bytes - output token first for exact output
            uint24(100), // 3 bytes - 0.01% fee for stablecoin pairs
            USDC // 20 bytes - input token last for exact output
        );

        SwapParams memory swapParams = SwapParams({swapEngine: SwapEngine.UNISWAP_V3, poolInfo: poolInfo});
        mockContract.registerPriceAdaptor(address(mockPriceOracle), USDC, USDT, swapParams);

        mockContract.swap(amountOut, USDC, USDT);

        assertEq(IERC20(USDT).balanceOf(address(mockContract)), amountOut);
    }

    function test_RevertWhen_swap_asset_pair_not_registered() public {
        uint128 amountOut = 1000e6;
        deal(USDC, address(mockContract), amountOut * 2);

        vm.expectRevert(abi.encodeWithSelector(AssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        mockContract.swap(amountOut, USDC, address(0));
    }

    function test_quote() public view {
        uint256 amountIn = 1000e6;
        uint256 quote = mockContract.quote(amountIn, USDC, USDT);
        assertEq(quote, amountIn);

        uint256 newQuote = mockContract.quote(amountIn, USDT, USDC);
        assertEq(newQuote, amountIn);
    }

    function test_RevertWhen_quote_asset_pair_not_registered() public {
        uint256 amountIn = 1000e6;
        vm.expectRevert(abi.encodeWithSelector(AssetPriceOracleAndSwapper.AssetPairNotRegistered.selector));
        mockContract.quote(amountIn, USDC, address(0));
    }
}
