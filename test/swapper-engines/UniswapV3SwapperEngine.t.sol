// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {UniswapV3SwapperEngine} from "src/swapper-engines/UniswapV3SwapperEngine.sol";
import {TestDeployer} from "test/utils/TestDeployer.sol";
import {UniswapHelper, UniswapAddressbook} from "utils/UniswapHelper.sol";

/// @notice Mock contract that can delegatecall to UniswapV3SwapperEngine
contract DelegateCallProxy {
    address public implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @notice Test contract that extends UniswapV3SwapperEngine to expose internal functions for testing
contract TestUniswapV3SwapperEngine is UniswapV3SwapperEngine {
    constructor(address _universalRouter, address _permit2, address _quoterV2)
        UniswapV3SwapperEngine(_universalRouter, _permit2, _quoterV2)
    {}

    /// @notice Exposes _reversePath for testing
    function reversePath(bytes memory poolInfo) external pure returns (bytes memory) {
        return _reversePath(poolInfo);
    }
}

contract UniswapV3SwapperEngineTest is TestDeployer, UniswapHelper {
    UniswapV3SwapperEngine public swapperEngine;
    TestUniswapV3SwapperEngine public testSwapperEngine;
    DelegateCallProxy public proxy;

    function setUp() public override {
        super.setUp();

        UniswapAddressbook memory uniswapAddressBook = _getUniswapAddressBook();

        swapperEngine = new UniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.quoterV2
        );

        testSwapperEngine = new TestUniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.quoterV2
        );

        proxy = new DelegateCallProxy(address(swapperEngine));
    }

    // ============ name() Tests ============ //

    function test_name() public view {
        assertEq(swapperEngine.name(), "UniswapV3 Swapper Engine");
    }

    // ============ getAssetAddresses() Tests ============ //

    function test_getAssetAddresses_singlePool() public view {
        // Single pool path: tokenA (20 bytes) + fee (3 bytes) + tokenB (20 bytes) = 43 bytes
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        (address assetA, address assetB) = swapperEngine.getAssetAddresses(poolInfo);

        assertEq(assetA, USDC, "First asset should be USDC");
        assertEq(assetB, USDT, "Last asset should be USDT");
    }

    function test_getAssetAddresses_multiHopPool() public view {
        // Multi-hop path: rETH -> WETH -> USDC
        // rETH (20) + fee (3) + WETH (20) + fee (3) + USDC (20) = 66 bytes
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        (address assetA, address assetB) = swapperEngine.getAssetAddresses(poolInfo);

        assertEq(assetA, rETH, "First asset should be rETH");
        assertEq(assetB, USDC, "Last asset should be USDC");
    }

    function test_RevertWhen_getAssetAddresses_poolInfoTooShort() public {
        bytes memory poolInfo = abi.encodePacked(uint8(1), uint8(2)); // Only 2 bytes

        vm.expectRevert("PoolInfo too short");
        swapperEngine.getAssetAddresses(poolInfo);
    }

    // ============ reversePath() Tests ============ //

    function test_reversePath_singlePool() public view {
        // Single pool: just one token (20 bytes)
        bytes memory poolInfo = abi.encodePacked(USDC);

        bytes memory reversed = testSwapperEngine.reversePath(poolInfo);

        // Single pool reversed should be the same
        assertEq(reversed.length, poolInfo.length, "Length should match");
        assertEq(reversed, poolInfo, "Single pool path should remain unchanged when reversed");

        // Verify the token address is preserved
        (address originalA, address originalB) = swapperEngine.getAssetAddresses(poolInfo);
        (address reversedA, address reversedB) = swapperEngine.getAssetAddresses(reversed);
        assertEq(originalA, reversedA, "First token should match");
        assertEq(originalB, reversedB, "Last token should match");
    }

    function test_reversePath_twoPools() public view {
        // Two pools: token0 (20) + fee0 (3) + token1 (20) = 43 bytes
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        bytes memory reversed = testSwapperEngine.reversePath(poolInfo);

        // Verify length
        assertEq(reversed.length, poolInfo.length, "Length should match");

        // Verify tokens are swapped
        (address originalFirst, address originalLast) = swapperEngine.getAssetAddresses(poolInfo);
        (address reversedFirst, address reversedLast) = swapperEngine.getAssetAddresses(reversed);

        assertEq(originalFirst, reversedLast, "Original first should be reversed last");
        assertEq(originalLast, reversedFirst, "Original last should be reversed first");

        // Verify fee is preserved (in the middle)
        uint24 originalFee;
        uint24 reversedFee;
        assembly {
            originalFee := shr(232, mload(add(poolInfo, 0x34))) // Read fee at offset 20 (0x14 + 0x20)
            reversedFee := shr(232, mload(add(reversed, 0x34))) // Read fee at offset 20
        }
        assertEq(originalFee, reversedFee, "Fee should be preserved");
    }

    function test_reversePath_multiHop() public view {
        // Multi-hop: rETH (20) + fee0 (3) + WETH (20) + fee1 (3) + USDC (20) = 66 bytes
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC);

        bytes memory reversed = testSwapperEngine.reversePath(poolInfo);

        // Verify length
        assertEq(reversed.length, poolInfo.length, "Length should match");

        // Verify first and last tokens are swapped
        (address originalFirst, address originalLast) = swapperEngine.getAssetAddresses(poolInfo);
        (address reversedFirst, address reversedLast) = swapperEngine.getAssetAddresses(reversed);

        assertEq(originalFirst, reversedLast, "Original first (rETH) should be reversed last");
        assertEq(originalLast, reversedFirst, "Original last (USDC) should be reversed first");

        // Verify intermediate token (WETH) is in the middle
        address reversedMiddle;
        assembly {
            // Read token at offset 23 (after first token + fee)
            let middleOffset := add(reversed, 0x37) // 0x20 (length) + 0x17 (23 bytes)
            reversedMiddle := shr(96, mload(middleOffset))
        }
        assertEq(reversedMiddle, WETH, "WETH should be in the middle of reversed path");

        // Verify fees are preserved in reverse order
        uint24 originalFee0;
        uint24 originalFee1;
        uint24 reversedFee0;
        uint24 reversedFee1;
        assembly {
            // Original fees
            originalFee0 := shr(232, mload(add(poolInfo, 0x34))) // Offset 20
            originalFee1 := shr(232, mload(add(poolInfo, 0x4B))) // Offset 43

            // Reversed fees (should be swapped)
            reversedFee0 := shr(232, mload(add(reversed, 0x34))) // Offset 20
            reversedFee1 := shr(232, mload(add(reversed, 0x4B))) // Offset 43
        }
        assertEq(originalFee0, reversedFee1, "First fee should become last fee");
        assertEq(originalFee1, reversedFee0, "Last fee should become first fee");
    }

    function test_reversePath_doubleReverse() public view {
        // Reversing twice should give the original path
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(100), USDT, uint24(500), WETH);

        bytes memory reversed = testSwapperEngine.reversePath(poolInfo);
        bytes memory doubleReversed = testSwapperEngine.reversePath(reversed);

        // Double reversed should equal original
        assertEq(doubleReversed.length, poolInfo.length, "Length should match");
        assertEq(keccak256(doubleReversed), keccak256(poolInfo), "Double reverse should equal original");
    }

    function test_reversePath_preservesAllTokensAndFees() public view {
        // Verify all tokens and fees are preserved in the reversed path
        bytes memory poolInfo = abi.encodePacked(rETH, uint24(100), WETH, uint24(500), USDC, uint24(3000), USDT);

        bytes memory reversed = testSwapperEngine.reversePath(poolInfo);

        // Extract tokens using getAssetAddresses and manual extraction
        (address originalFirst, address originalLast) = swapperEngine.getAssetAddresses(poolInfo);
        (address reversedFirst, address reversedLast) = swapperEngine.getAssetAddresses(reversed);

        // Verify first and last tokens are swapped
        assertEq(originalFirst, reversedLast, "Original first (rETH) should be reversed last");
        assertEq(originalLast, reversedFirst, "Original last (USDT) should be reversed first");

        // Extract intermediate tokens by reading bytes directly
        // Original: rETH (0-19), fee (20-22), WETH (23-42), fee (43-45), USDC (46-65), fee (66-68), USDT (69-88)
        address originalToken1; // WETH at offset 23
        address originalToken2; // USDC at offset 46
        assembly {
            let ptr := add(poolInfo, 0x20) // Skip length word
            // Read WETH: bytes 23-42 (offset 23 from data start)
            let word1 := mload(add(ptr, 23))
            originalToken1 := shr(96, word1)
            // Read USDC: bytes 46-65 (offset 46 from data start)
            let word2 := mload(add(ptr, 46))
            originalToken2 := shr(96, word2)
        }

        // Reversed: USDT (0-19), fee (20-22), USDC (23-42), fee (43-45), WETH (46-65), fee (66-68), rETH (69-88)
        address reversedToken1; // USDC at offset 23
        address reversedToken2; // WETH at offset 46
        assembly {
            let ptr := add(reversed, 0x20) // Skip length word
            // Read USDC: bytes 23-42 (offset 23 from data start)
            let word1 := mload(add(ptr, 23))
            reversedToken1 := shr(96, word1)
            // Read WETH: bytes 46-65 (offset 46 from data start)
            let word2 := mload(add(ptr, 46))
            reversedToken2 := shr(96, word2)
        }

        // Verify intermediate tokens are swapped
        assertEq(originalToken1, reversedToken2, "WETH should be in correct reversed position");
        assertEq(originalToken2, reversedToken1, "USDC should be in correct reversed position");

        // Extract fees from original
        // Original: rETH (0-19), fee0=100 (20-22), WETH (23-42), fee1=500 (43-45), USDC (46-65), fee2=3000 (66-68), USDT (69-88)
        uint24 originalFee0;
        uint24 originalFee1;
        uint24 originalFee2;
        assembly {
            originalFee0 := shr(232, mload(add(poolInfo, 0x34))) // Offset 20
            originalFee1 := shr(232, mload(add(poolInfo, 0x4B))) // Offset 43
            originalFee2 := shr(232, mload(add(poolInfo, 0x62))) // Offset 66
        }

        // Extract fees from reversed
        // Reversed: USDT (0-19), fee2=3000 (20-22), USDC (23-42), fee1=500 (43-45), WETH (46-65), fee0=100 (66-68), rETH (69-88)
        uint24 reversedFee0;
        uint24 reversedFee1;
        uint24 reversedFee2;
        assembly {
            reversedFee0 := shr(232, mload(add(reversed, 0x34))) // Offset 20
            reversedFee1 := shr(232, mload(add(reversed, 0x4B))) // Offset 43
            reversedFee2 := shr(232, mload(add(reversed, 0x62))) // Offset 66
        }

        // Verify fees are swapped in reverse order
        assertEq(originalFee0, reversedFee2, "First fee should become last");
        assertEq(originalFee1, reversedFee1, "Middle fee should stay in middle");
        assertEq(originalFee2, reversedFee0, "Last fee should become first");
    }

    function test_RevertWhen_reversePath_poolInfoTooShort() public {
        bytes memory poolInfo = abi.encodePacked(uint8(1), uint8(2)); // Only 2 bytes

        vm.expectRevert("PoolInfo too short");
        testSwapperEngine.reversePath(poolInfo);
    }

    // ============ onlyDelegateCall Modifier Tests ============ //

    function test_RevertWhen_swapForInput_calledDirectly() public {
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), USDT);

        vm.expectRevert(UniswapV3SwapperEngine.OnlyDelegateCall.selector);
        swapperEngine.swapForInput(poolInfo, 1000e6, 900e6, USDC, USDT);
    }

    function test_RevertWhen_swapForOutput_calledDirectly() public {
        bytes memory poolInfo = abi.encodePacked(USDT, uint24(500), USDC);

        vm.expectRevert(UniswapV3SwapperEngine.OnlyDelegateCall.selector);
        swapperEngine.swapForOutput(poolInfo, 1000e6, 1100e6, USDC, USDT);
    }

    // ============ swapForInput() via delegatecall Tests ============ //

    function test_swapForInput() public {
        uint256 amountIn = 1000e6;
        uint256 amountOutMin = 990e6;

        // Deal USDC to proxy
        deal(USDC, address(proxy), amountIn);

        // Approve permit2 to spend USDC
        vm.prank(address(proxy));
        IERC20(USDC).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Path: USDC -> USDT (EXACT_IN format: input -> fee -> output)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDT
        );

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector, poolInfo, amountIn, amountOutMin, USDC, USDT
                )
            );

        assertTrue(success, "Swap should succeed");

        uint256 amountOut = abi.decode(result, (uint256));
        assertGt(amountOut, 0, "Should receive output tokens");
        assertGe(amountOut, amountOutMin, "Should receive at least minimum output");
    }

    function test_swapForInput_reversedPath() public {
        uint256 amountIn = 1000e6;
        uint256 amountOutMin = 990e6;

        // Deal USDC to proxy
        deal(USDC, address(proxy), amountIn);

        // Approve permit2 to spend USDC
        vm.prank(address(proxy));
        IERC20(USDC).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Path is reversed: USDT -> USDC (but we're swapping USDC -> USDT)
        // The contract should handle this by detecting the reversal
        bytes memory poolInfo = abi.encodePacked(USDT, uint24(100), USDC);

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector,
                    poolInfo,
                    amountIn,
                    amountOutMin,
                    USDC, // base = input
                    USDT // swap = output
                )
            );

        assertTrue(success, "Swap with reversed path should succeed");

        uint256 amountOut = abi.decode(result, (uint256));
        assertGt(amountOut, 0, "Should receive output tokens");
    }

    function test_RevertWhen_swapForInput_poolMismatch() public {
        uint256 amountIn = 1000e6;

        // Path with wrong tokens
        bytes memory poolInfo = abi.encodePacked(
            WETH, // Wrong token
            uint24(500),
            rETH // Wrong token
        );

        // Execute swap via delegatecall - should revert with PoolMismatch
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector,
                    poolInfo,
                    amountIn,
                    0,
                    USDC, // Doesn't match path
                    USDT // Doesn't match path
                )
            );

        assertFalse(success, "Should fail with pool mismatch");
        // Check for PoolMismatch error
        assertEq(bytes4(result), UniswapV3SwapperEngine.PoolMismatch.selector);
    }

    // ============ swapForOutput() via delegatecall Tests ============ //

    function test_swapForOutput() public {
        uint256 amountOut = 1000e6;
        uint256 amountInMax = 1100e6;

        // Deal USDC to proxy (more than needed for slippage)
        deal(USDC, address(proxy), amountInMax);

        // Approve permit2 to spend USDC
        vm.prank(address(proxy));
        IERC20(USDC).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Path: USDT -> USDC (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDC
        );

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    amountInMax,
                    USDC, // base = input
                    USDT // swap = output
                )
            );

        assertTrue(success, "Swap should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend input tokens");
        assertLe(amountIn, amountInMax, "Should not exceed max input");

        // Verify we received the exact output amount
        assertEq(IERC20(USDT).balanceOf(address(proxy)), amountOut, "Should receive exact output amount");
    }

    function test_swapForOutput_reversedPath() public {
        uint256 amountOut = 1000e6;
        uint256 amountInMax = 1100e6;

        // Deal USDC to proxy
        deal(USDC, address(proxy), amountInMax);

        // Approve permit2 to spend USDC
        vm.prank(address(proxy));
        IERC20(USDC).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Path is reversed: USDC -> USDT (but for EXACT_OUT we want USDT as output)
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(100), USDT);

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    amountInMax,
                    USDC, // base = input
                    USDT // swap = output
                )
            );

        assertTrue(success, "Swap with reversed path should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend input tokens");
    }

    function test_RevertWhen_swapForOutput_poolMismatch() public {
        uint256 amountOut = 1000e6;

        // Path with wrong tokens
        bytes memory poolInfo = abi.encodePacked(WETH, uint24(500), rETH);

        // Execute swap via delegatecall - should revert with PoolMismatch
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    type(uint256).max,
                    USDC, // Doesn't match path
                    USDT // Doesn't match path
                )
            );

        assertFalse(success, "Should fail with pool mismatch");
        assertEq(bytes4(result), UniswapV3SwapperEngine.PoolMismatch.selector);
    }

    // ============ Multi-hop Swap Tests ============ //

    function test_swapForInput_multiHop() public {
        uint256 amountIn = 1e18; // 1 rETH

        // Deal rETH to proxy
        deal(rETH, address(proxy), amountIn);

        // Approve permit2 to spend rETH
        vm.prank(address(proxy));
        IERC20(rETH).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Multi-hop path: rETH -> WETH -> USDC (EXACT_IN)
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee for rETH/WETH
            WETH,
            uint24(500), // 0.05% fee for WETH/USDC
            USDC
        );

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector,
                    poolInfo,
                    amountIn,
                    0, // No minimum for test
                    rETH,
                    USDC
                )
            );

        assertTrue(success, "Multi-hop swap should succeed");

        uint256 amountOut = abi.decode(result, (uint256));
        assertGt(amountOut, 0, "Should receive USDC");
    }

    function test_swapForOutput_multiHop() public {
        uint256 amountOut = 1000e6; // 1000 USDC

        // Deal rETH to proxy (more than needed)
        deal(rETH, address(proxy), 10e18);

        // Approve permit2 to spend rETH
        vm.prank(address(proxy));
        IERC20(rETH).approve(_getUniswapAddressBook().uniswapAddresses.permit2, type(uint256).max);

        // Multi-hop path: USDC -> WETH -> rETH (EXACT_OUT format: output -> intermediate -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(500), // 0.05% fee for WETH/USDC
            WETH,
            uint24(100), // 0.01% fee for rETH/WETH
            rETH
        );

        // Execute swap via delegatecall
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    type(uint256).max, // Allow any input for test
                    rETH,
                    USDC
                )
            );

        assertTrue(success, "Multi-hop swap should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend rETH");

        // Verify we received the exact output
        assertEq(IERC20(USDC).balanceOf(address(proxy)), amountOut, "Should receive exact USDC amount");
    }
}
