// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {UniswapV3SwapperEngine} from "src/swapper-engines/UniswapV3SwapperEngine.sol";
import {ISwapperEngine} from "src/interfaces/ISwapperEngine.sol";
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
    constructor(address _universalRouter, address _permit2, address _quoter)
        UniswapV3SwapperEngine(_universalRouter, _permit2, _quoter)
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
            uniswapAddressBook.uniswapAddresses.viewQuoterV3
        );

        testSwapperEngine = new TestUniswapV3SwapperEngine(
            uniswapAddressBook.uniswapAddresses.universalRouter,
            uniswapAddressBook.uniswapAddresses.permit2,
            uniswapAddressBook.uniswapAddresses.viewQuoterV3
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

        vm.expectRevert(ISwapperEngine.InvalidPoolInfo.selector);
        swapperEngine.getAssetAddresses(poolInfo);
    }

    // ============ reversePath() Tests ============ //

    function test_reversePath_singlePool() public view {
        // Single pool path: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes) = 43 bytes
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

        vm.expectRevert(ISwapperEngine.OnlyDelegateCall.selector);
        swapperEngine.swapForInput(poolInfo, 1000e6, 900e6, USDC, USDT);
    }

    function test_RevertWhen_swapForOutput_calledDirectly() public {
        bytes memory poolInfo = abi.encodePacked(USDT, uint24(500), USDC);

        vm.expectRevert(ISwapperEngine.OnlyDelegateCall.selector);
        swapperEngine.swapForOutput(poolInfo, 1000e6, 1100e6, USDC, USDT);
    }

    // ============ getQuote() Tests ============ //

    function test_getQuote() public {
        uint256 amountIn = 1000e6; // 1000 USDT (quote)

        // Path: USDT -> USDC (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDC
        );

        // Execute quote via delegatecall: given amountIn of USDT (quote), how much USDC (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, USDC, USDT));

        require(success, "Quote should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote (should be close to amountIn for stablecoin pair)
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertLt(
            amountOut, amountIn * 101 / 100, "Amount out should be less than 101% of amount in (accounting for fees)"
        );
        assertGt(amountOut, amountIn * 99 / 100, "Amount out should be greater than 99% of amount in");
    }

    function test_getQuote_reversedPath() public {
        uint256 amountIn = 1000e6; // 1000 USDT (quote)

        // Path: USDC -> USDT (will be reversed internally to USDT -> USDC for EXACT_OUT)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(100), // 0.01% fee
            USDT
        );

        // Execute quote via delegatecall with reversed path: given amountIn of USDT (quote), how much USDC (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, USDC, USDT));

        require(success, "Quote should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertLt(amountOut, amountIn * 101 / 100, "Amount out should be less than 101% of amount in");
        assertGt(amountOut, amountIn * 99 / 100, "Amount out should be greater than 99% of amount in");
    }

    function test_getQuote_multiHop() public {
        uint256 amountIn = 3000e6; // 3000 USDT (quote)

        // Multi-hop path: USDT -> USDC -> WETH (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee
            USDC,
            uint24(3000), // 0.3% fee
            WETH
        );

        // Execute quote via delegatecall: given amountIn of USDT (quote), how much WETH (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, WETH, USDT));

        require(success, "Multi-hop quote should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote (should be significant amount of WETH for 3000 USDT)
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(amountOut, 1e15, "Should get at least 0.001 WETH for 3000 USDT");
    }

    function test_RevertWhen_getQuote_poolMismatch() public {
        uint256 amountIn = 1000e6;

        // Path: USDC -> WETH (but we're asking for USDC (base) and USDT (quote))
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(500), WETH);

        // Execute quote via delegatecall - should revert with InvalidPoolInfo
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, USDC, USDT));
        assertFalse(success, "Should revert with InvalidPoolInfo");
        // casting to 'bytes4' is safe because error selectors are always 4 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(result), ISwapperEngine.InvalidPoolInfo.selector, "Should revert with InvalidPoolInfo");
    }

    function test_getQuote_USDC_to_rETH() public {
        uint256 amountIn = 1e18; // 1 rETH (quote)

        // Path: USDC -> WETH -> rETH (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(500), // 0.05% fee
            WETH,
            uint24(100), // 0.01% fee
            rETH
        );

        // Execute quote via delegatecall: given amountIn of USDC (quote), how much rETH (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, USDC, rETH));

        require(success, "USDC to rETH quote should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(amountOut, 2500e6, "Should get significant 3000 USDC for 1 rETH");
        assertLt(amountOut, 7500e6, "Should get significant less than 7500 USDC for 1 rETH");
    }

    function test_getQuote_rETH_to_USDC() public {
        uint256 amountIn = 3000e6; // 3000 USDC (quote)

        // Path: USDC -> WETH -> rETH (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(500), // 0.05% fee
            WETH,
            uint24(100), // 0.01% fee
            rETH
        );

        // Execute quote via delegatecall: given amountIn of USDC (quote), how much rETH (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, rETH, USDC));

        require(success, "USDC to rETH quote should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(amountOut, 1e15, "Should get significant rETH for 3000 USDC");
    }

    function test_getQuote_rETH_to_USDC_reversedPath() public {
        uint256 amountIn = 3000e6; // 3000 USDC (quote)

        // Path: rETH -> WETH -> USDC (will be reversed internally to USDC -> WETH -> rETH for EXACT_OUT)
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee
            WETH,
            uint24(500), // 0.05% fee
            USDC
        );

        // Execute quote via delegatecall with reversed path: given amountIn of USDC (quote), how much rETH (base)?
        (bool success, bytes memory result) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountIn, rETH, USDC));

        require(success, "USDC to rETH quote with reversed path should succeed");
        uint256 amountOut = abi.decode(result, (uint256));

        // Verify we got a valid quote
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(amountOut, 1e15, "Should get significant rETH for 3000 USDC");

        // The quote should be similar to the non-reversed path (within reasonable tolerance)
        // Get the quote from the normal path for comparison
        bytes memory normalPath = abi.encodePacked(USDC, uint24(500), WETH, uint24(100), rETH);

        (bool success2, bytes memory result2) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, normalPath, amountIn, rETH, USDC));

        require(success2, "Normal path quote should succeed");
        uint256 amountOutNormal = abi.decode(result2, (uint256));

        // Both quotes should be very close (within 1% difference due to path reversal and rounding)
        uint256 diff;
        if (amountOut > amountOutNormal) {
            diff = amountOut - amountOutNormal;
        } else {
            diff = amountOutNormal - amountOut;
        }

        uint256 tolerance = amountOutNormal / 100; // 1% tolerance
        assertLt(diff, tolerance, "Reversed path quote should be within 1% of normal path quote");
    }

    // ============ swapForInput() via delegatecall Tests ============ //

    function test_swapForInput() public {
        uint256 amountIn = 1000e6;
        uint256 amountOutMin = 990e6;

        // Deal USDT to proxy (swap is now the input asset)
        deal(USDT, address(proxy), amountIn);

        // Path: USDT -> USDC (EXACT_IN format: input -> fee -> output)
        bytes memory poolInfo = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDC
        );

        // Initialize approvals via onInit
        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap amountIn of USDT (swap) -> get USDC (base)
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

        // Verify we received USDC (base) as output
        assertGt(IERC20(USDC).balanceOf(address(proxy)), 0, "Should receive USDC");
    }

    function test_swapForInput_reversedPath() public {
        uint256 amountIn = 1000e6;
        uint256 amountOutMin = 990e6;

        // Deal USDT to proxy (swap is now the input asset)
        deal(USDT, address(proxy), amountIn);

        // Path is reversed: USDC -> USDT (but we're swapping USDT -> USDC)
        // The contract should handle this by detecting the reversal
        bytes memory poolInfo = abi.encodePacked(USDC, uint24(100), USDT);

        // Initialize approvals via onInit
        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap amountIn of USDT (swap) -> get USDC (base)
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector,
                    poolInfo,
                    amountIn,
                    amountOutMin,
                    USDC, // base = output
                    USDT // swap = input
                )
            );

        assertTrue(success, "Swap with reversed path should succeed");

        uint256 amountOut = abi.decode(result, (uint256));
        assertGt(amountOut, 0, "Should receive output tokens");

        // Verify we received USDC (base) as output
        assertGt(IERC20(USDC).balanceOf(address(proxy)), 0, "Should receive USDC");
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
        assertFalse(success, "Should revert with PoolMismatch");
        // casting to 'bytes4' is safe because error selectors are always 4 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(result), UniswapV3SwapperEngine.PoolMismatch.selector, "Should revert with PoolMismatch");
    }

    // ============ swapForOutput() via delegatecall Tests ============ //

    function test_swapForOutput_singleHop() public {
        uint256 amountOut = 1000e6;
        uint256 amountInMax = 1100e6;

        // Deal USDT to proxy (swap is now the input asset, more than needed for slippage)
        deal(USDT, address(proxy), amountInMax);

        // Path: USDC -> USDT (EXACT_OUT format: output -> fee -> input)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDT
        );

        // Initialize approvals via onInit
        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap USDT (swap) -> get amountOut of USDC (base)
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    amountInMax,
                    USDC, // base = output
                    USDT // swap = input
                )
            );

        assertTrue(success, "Swap should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend input tokens");
        assertLe(amountIn, amountInMax, "Should not exceed max input");

        // Verify we received the exact output amount of USDC (base)
        assertEq(IERC20(USDC).balanceOf(address(proxy)), amountOut, "Should receive exact output amount");
    }

    function test_swapForOutput_reversedPath() public {
        uint256 amountOut = 1000e6;
        uint256 amountInMax = 1100e6;

        // Deal USDT to proxy (swap is now the input asset)
        deal(USDT, address(proxy), amountInMax);

        // Path is reversed: USDT -> USDC (but for EXACT_OUT we want USDC as output)
        bytes memory poolInfo = abi.encodePacked(USDT, uint24(100), USDC);

        // Initialize approvals via onInit
        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap USDT (swap) -> get amountOut of USDC (base)
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    amountInMax,
                    USDC, // base = output
                    USDT // swap = input
                )
            );

        assertTrue(success, "Swap with reversed path should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend input tokens");

        // Verify we received USDC (base) as output
        assertEq(IERC20(USDC).balanceOf(address(proxy)), amountOut, "Should receive exact output amount");
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
        assertFalse(success, "Should revert with PoolMismatch");
        // casting to 'bytes4' is safe because error selectors are always 4 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(result), UniswapV3SwapperEngine.PoolMismatch.selector, "Should revert with PoolMismatch");
    }

    // ============ Multi-hop Swap Tests ============ //

    function test_swapForInput_multiHop() public {
        uint256 amountIn = 3000e6; // 3000 USDC (swap is now the input asset)

        // Deal USDC to proxy
        deal(USDC, address(proxy), amountIn);

        // Multi-hop path: USDC -> WETH -> rETH (EXACT_IN: swap -> base)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(500), // 0.05% fee for WETH/USDC
            WETH,
            uint24(100), // 0.01% fee for rETH/WETH
            rETH
        );

        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));

        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap amountIn of USDC (swap) -> get rETH (base)
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForInput.selector,
                    poolInfo,
                    amountIn,
                    0, // No minimum for test
                    rETH, // base = output
                    USDC // swap = input
                )
            );

        assertTrue(success, "Multi-hop swap should succeed");

        uint256 amountOut = abi.decode(result, (uint256));
        assertGt(amountOut, 0, "Should receive rETH");

        // Verify we received rETH (base) as output
        assertGt(IERC20(rETH).balanceOf(address(proxy)), 0, "Should receive rETH");
    }

    function test_swapForOutput_multiHop() public {
        uint256 amountOut = 1e18; // 1 rETH (base is now the output asset)

        // Deal USDC to proxy (swap is now the input asset, more than needed)
        deal(USDC, address(proxy), 10000e6);

        uint256 usdcStartingBalance = IERC20(USDC).balanceOf(address(proxy));

        // Multi-hop path: rETH -> WETH -> USDC (EXACT_OUT format: output -> intermediate -> input)
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee for rETH/WETH
            WETH,
            uint24(500), // 0.05% fee for WETH/USDC
            USDC
        );

        // Initialize approvals via onInit
        (bool successOnInit,) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(successOnInit, "onInit should succeed");

        // Execute swap via delegatecall: swap USDC (swap) -> get amountOut of rETH (base)
        (bool success, bytes memory result) = address(proxy)
            .call(
                abi.encodeWithSelector(
                    UniswapV3SwapperEngine.swapForOutput.selector,
                    poolInfo,
                    amountOut,
                    type(uint256).max, // Allow any input for test
                    rETH, // base = output
                    USDC // swap = input
                )
            );

        assertTrue(success, "Multi-hop swap should succeed");

        uint256 amountIn = abi.decode(result, (uint256));
        assertGt(amountIn, 0, "Should spend USDC");

        // Verify we received rETH (base) as output
        assertEq(IERC20(rETH).balanceOf(address(proxy)), amountOut, "Should receive exact output amount");

        // Execute swap via delegatecall: swap USDC (swap) -> get amountOut of rETH (base)
        (bool success2, bytes memory qoute) = address(proxy)
            .call(abi.encodeWithSelector(UniswapV3SwapperEngine.getQuote.selector, poolInfo, amountOut, USDC, rETH));

        assertTrue(success2, "Quote should succeed");

        // Verify we received the exact output
        assertApproxEqAbs(
            usdcStartingBalance - IERC20(USDC).balanceOf(address(proxy)),
            abi.decode(qoute, (uint256)),
            10e6,
            "Should receive exact USDC amount"
        );
    }

    function test_getQuote_largeAmount() public view {
        // Multi-hop path: rETH -> WETH -> USDC (EXACT_OUT format: output -> intermediate -> input)
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee for rETH/WETH
            WETH,
            uint24(500), // 0.05% fee for WETH/USDC
            USDC
        );

        uint256 amountOut = swapperEngine.getQuote(poolInfo, 1e15, rETH, USDC);
        assertGt(amountOut, 0, "Should receive amount out");
    }

    function test_getQuote_smallAmount() public view {
        // Multi-hop path: rETH -> WETH -> USDC (EXACT_OUT format: output -> intermediate -> input)
        bytes memory poolInfo = abi.encodePacked(
            rETH,
            uint24(100), // 0.01% fee for rETH/WETH
            WETH,
            uint24(500), // 0.05% fee for WETH/USDC
            USDC
        );

        uint256 amountOut = swapperEngine.getQuote(poolInfo, 1e7, rETH, USDC);
        assertGt(amountOut, 0, "Should receive amount out");
    }

    // ============ onInit() Tests ============ //

    function test_onInit() public {
        // Path: USDC -> USDT (EXACT_IN format: input -> fee -> output)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDT
        );

        // Call onInit via delegatecall
        (bool success,) = address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));

        assertTrue(success, "onInit should succeed");
    }

    function test_onInit_canBeCalledMultipleTimes() public {
        // Path: USDC -> USDT (EXACT_IN format: input -> fee -> output)
        bytes memory poolInfo = abi.encodePacked(
            USDC,
            uint24(100), // 0.01% fee for stablecoin pairs
            USDT
        );

        // Call onInit multiple times - should not revert
        (bool success1,) = address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(success1, "First onInit call should succeed");

        (bool success2,) = address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertTrue(success2, "Second onInit call should succeed");
    }

    function test_RevertWhen_onInit_invalidPoolInfo() public {
        // Invalid pool info (too short)
        bytes memory poolInfo = abi.encodePacked(uint8(1), uint8(2));

        // Call onInit via delegatecall - should revert with InvalidPoolInfo
        (bool success, bytes memory result) =
            address(proxy).call(abi.encodeWithSelector(UniswapV3SwapperEngine.onInit.selector, poolInfo));
        assertFalse(success, "Should revert with InvalidPoolInfo");
        // casting to 'bytes4' is safe because error selectors are always 4 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(result), ISwapperEngine.InvalidPoolInfo.selector, "Should revert with InvalidPoolInfo");
    }
}
