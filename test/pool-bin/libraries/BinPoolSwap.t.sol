// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {IHooks} from "../../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../../src/interfaces/IPoolManager.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {MockVault} from "../../../src/test/MockVault.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../../../src/types/PoolId.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../../src/pool-bin/libraries/BinPool.sol";
import {PackedUint128Math} from "../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../../src/pool-bin/libraries/math/SafeCast.sol";
import {BinPoolParametersHelper} from "../../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinTestHelper} from "../helpers/BinTestHelper.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {MockProtocolFeeController} from "../../../src/test/fee/MockProtocolFeeController.sol";

contract BinPoolSwapTest is BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using PackedUint128Math for bytes32;
    using BinPoolParametersHelper for bytes32;
    using SafeCast for uint256;

    MockVault public vault;
    BinPoolManager public poolManager;

    uint24 immutable activeId = ID_ONE;

    PoolKey key;
    PoolId poolId;
    bytes32 poolParam;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vault = new MockVault();
        poolManager = new BinPoolManager(IVault(address(vault)), 500000);

        poolParam = poolParam.setBinStep(10);
        key = PoolKey({
            currency0: Currency.wrap(makeAddr("token0")),
            currency1: Currency.wrap(makeAddr("token1")),
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000),
            parameters: poolParam // binStep
        });
        poolId = key.toId();
    }

    function test_GetSwapInAndSwapOutSingleBin() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        (uint128 amountIn, uint128 amountOutLeft, uint128 fee1) = poolManager.getSwapIn(key, true, 1e18);
        assertEq(amountIn, 1003009027081243732); // expected 1e18 + around 0.3% fee
        assertEq(amountOutLeft, 0);
        assertEq(fee1, 3009027081243732);
        assertEq(amountIn - fee1, 1e18);

        (uint128 amountInLeft, uint128 amountOut, uint128 fee2) = poolManager.getSwapOut(key, true, amountIn);
        assertEq(amountInLeft, 0);
        assertEq(amountOut, 1e18);
        assertEq(fee2, fee1);

        // verify swap return same result
        BalanceDelta delta = poolManager.swap(key, true, amountIn, "");
        assertEq(delta.amount0(), -int128(amountIn));
        assertEq(delta.amount1(), 1e18);
    }

    function test_GetSwapInAndSwapOutMultipleBin() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        (uint128 amountIn, uint128 amountOutLeft, uint128 fee1) = poolManager.getSwapIn(key, true, 1e18);
        assertEq(amountIn, 1007534624899920784); // expected 1e18 + slippage + around 0.3% fee
        assertEq(amountOutLeft, 0);
        assertEq(fee1, 3022603874699769);
        assertGt(amountIn - fee1, 1e18); // amountIn - fee should be greater than 1e18 as swap across bin with slippage

        (uint128 amountInLeft, uint128 amountOut, uint128 fee2) = poolManager.getSwapOut(key, true, amountIn);
        assertEq(amountInLeft, 0);
        assertEq(amountOut, 1e18);
        assertEq(fee2, fee1);

        // verify swap return same result
        BalanceDelta delta = poolManager.swap(key, true, amountIn, "");
        assertEq(delta.amount0(), -int128(amountIn));
        assertEq(delta.amount1(), 1e18);
    }

    function test_SwapSingleBinWithProtocolFee() public {
        // Pre-req: set protocol fee at 0.1%
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 1000);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to active bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        (uint128 amountIn,, uint128 fee1) = poolManager.getSwapIn(key, true, 1e18);
        // total fee should be roughly 0.1% + 0.3% (1 - 0.1%) = 0.3997%
        assertApproxEqRel(fee1, 1e18 * 0.003997, 0.01e18);

        (,, uint128 fee2) = poolManager.getSwapOut(key, true, amountIn);
        assertEq(fee2, fee1);

        // Swap and verify protocol fee is 0.1%
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
        poolManager.swap(key, true, amountIn, "");
        assertApproxEqRel(poolManager.protocolFeesAccrued(key.currency0), fee1 / 4, 0.001e18);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_SwapMultipleBinWithProtocolFee() public {
        // Pre-req: set protocol fee at 0.1%
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 1000); // 0.1%
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to 10 bins
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        (uint128 amountIn,, uint128 fee1) = poolManager.getSwapIn(key, true, 1e18);
        assertEq(fee1, 4031147042767755);

        (,, uint128 fee2) = poolManager.getSwapOut(key, true, amountIn);
        assertEq(fee2, fee1);

        // Swap and verify protocol fee is 0.1%
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
        poolManager.swap(key, true, amountIn, "");

        // should be very close to 1/4 of fee. add 0.1% approxEq due to math
        assertApproxEqRel(poolManager.protocolFeesAccrued(key.currency0), fee1 / 4, 0.001e18);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function testFuzz_SwapInForY(uint128 amountOut) public {
        amountOut = uint128(bound(amountOut, 1, 1e18 - 1));

        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // amountIn: token0 in amt, amountOutLeft: token1 out amount
        (uint128 amountIn, uint128 amountOutLeft,) = poolManager.getSwapIn(key, true, amountOut);

        // pool should have deep liqudiity to swap and result in 0 amountOut
        assertEq(amountOutLeft, 0, "TestFuzz_SwapInForY::1");

        poolManager.swap(key, true, amountIn, "0x");

        // verify .getSwapIn match with swap result
        assertEq(vault.balanceDeltaOfPool(poolId).amount0(), -int128(amountIn), "TestFuzz_SwapInForY::2");
        assertEq(vault.balanceDeltaOfPool(poolId).amount1(), int128(amountOut), "TestFuzz_SwapInForY::3");
    }

    function testFuzz_SwapInForX(uint128 amountOut) public {
        amountOut = uint128(bound(amountOut, 1, 1e18 - 1));

        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // amountIn: token0 in amt, amountOutLeft: token1 out amount
        (uint128 amountIn, uint128 amountOutLeft,) = poolManager.getSwapIn(key, false, amountOut);

        assertEq(amountOutLeft, 0, "TestFuzz_SwapInForX::1");

        poolManager.swap(key, false, amountIn, "0x");

        // verify .getSwapIn match with swap result
        assertEq(vault.balanceDeltaOfPool(poolId).amount0(), int128(amountOut), "TestFuzz_SwapInForX::2");
        assertEq(vault.balanceDeltaOfPool(poolId).amount1(), -int128(amountIn), "TestFuzz_SwapInForX::3");
    }

    function testFuzz_SwapOutForY(uint128 amountIn) public {
        amountIn = uint128(bound(amountIn, 1, 1e18));

        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // (uint128 amountInLeft, uint128 amountOut, ) = pairWnative.getSwapOut(amountIn, true);
        (uint128 amountInLeft, uint128 amountOut,) = poolManager.getSwapOut(key, true, amountIn);

        if (amountOut == 0) return;

        assertEq(amountInLeft, 0, "TestFuzz_SwapOutForY::1");

        poolManager.swap(key, true, amountIn, "0x");

        // verify .getSwapIn match with swap result
        assertEq(vault.balanceDeltaOfPool(poolId).amount0(), -int128(amountIn), "TestFuzz_SwapOutForY::2");
        assertEq(vault.balanceDeltaOfPool(poolId).amount1(), int128(amountOut), "TestFuzz_SwapOutForY::3");
    }

    function testFuzz_SwapOutForX(uint128 amountIn) public {
        amountIn = uint128(bound(amountIn, 1, 1e18));

        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // (uint128 amountInLeft, uint128 amountOut,) = pairWnative.getSwapOut(amountIn, false);
        (uint128 amountInLeft, uint128 amountOut,) = poolManager.getSwapOut(key, false, amountIn);

        if (amountOut == 0) return;

        assertEq(amountInLeft, 0, "TestFuzz_SwapOutForX::1");

        poolManager.swap(key, false, amountIn, "0x");

        // verify .getSwapIn match with swap result
        assertEq(vault.balanceDeltaOfPool(poolId).amount0(), int128(amountOut), "TestFuzz_SwapOutForY::2");
        assertEq(vault.balanceDeltaOfPool(poolId).amount1(), -int128(amountIn), "TestFuzz_SwapOutForY::3");
    }

    function test_revert_SwapInsufficientAmountIn() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 0;

        vm.expectRevert(IBinPoolManager.InsufficientAmountIn.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(IBinPoolManager.InsufficientAmountIn.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function test_revert_SwapInsufficientAmountOut() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 1;

        vm.expectRevert(BinPool.BinPool__InsufficientAmountOut.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(BinPool.BinPool__InsufficientAmountOut.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function test_revert_SwapOutOfLiquidity() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // pool only have 1e18 token0, 1e18 token1
        uint128 amountIn = 2e18;

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function _getSwapFee(uint24 fee0, uint24 fee1) internal pure returns (uint24) {
        return fee0 + (fee1 << 12);
    }
}
