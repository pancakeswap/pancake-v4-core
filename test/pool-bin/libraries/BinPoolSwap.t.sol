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
import {PoolId} from "../../../src/types/PoolId.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../../src/pool-bin/libraries/BinPool.sol";
import {PackedUint128Math} from "../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../../src/pool-bin/libraries/math/SafeCast.sol";
import {BinPoolParametersHelper} from "../../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinTestHelper} from "../helpers/BinTestHelper.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {MockProtocolFeeController} from "../../../src/test/fee/MockProtocolFeeController.sol";

contract BinPoolSwapTest is BinTestHelper {
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

    function test_exactInputSingleBin_SwapForY() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        BalanceDelta delta = poolManager.swap(key, true, -int128(1e18), "");
        assertEq(delta.amount0(), -int128(1e18));
        assertEq(delta.amount1(), 997000000000000000);
    }

    function test_exactInputSingleBin_SwapForX() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        BalanceDelta delta = poolManager.swap(key, false, -int128(1e18), "");
        assertEq(delta.amount0(), 997000000000000000);
        assertEq(delta.amount1(), -1e18);
    }

    function test_exactOutputSingleBin_SwapForY() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        BalanceDelta delta = poolManager.swap(key, true, 1e18, "");
        assertEq(delta.amount0(), -1003009027081243732);
        assertEq(delta.amount1(), 1e18);
    }

    function test_exactOutputSingleBin_SwapForX() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        BalanceDelta delta = poolManager.swap(key, false, 1e18, "");
        assertEq(delta.amount0(), 1e18);
        assertEq(delta.amount1(), -1003009027081243732);
    }

    function test_exactInputMultipleBin() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        BalanceDelta delta = poolManager.swap(key, true, -1e18, "");
        assertEq(delta.amount0(), -1e18);
        assertEq(delta.amount1(), 992555250358834498);
    }

    function test_exactOutputMultipleBin() public {
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        BalanceDelta delta = poolManager.swap(key, true, 1e18, "");
        assertEq(delta.amount0(), -1007534624899920784);
        assertEq(delta.amount1(), 1e18);
    }

    function test_SwapWithProtocolFee_ExactIn_SwapForY() public {
        // Pre-req: set protocol fee at 0.1% for token0 and 0.05% for token1
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 500);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to active bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        // before swap
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);

        // swap - swapForY
        BalanceDelta delta = poolManager.swap(key, true, -1e18, "");
        assertEq(delta.amount0(), -1e18);
        assertEq(delta.amount1(), 996003000000000000);

        // after swap, verify 0.1% fee
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0.001 * 1e18);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_SwapWithProtocolFee_ExactIn_SwapForX() public {
        // Pre-req: set protocol fee at 0.1% for token0 and 0.05% for token1
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 500);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to active bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        // before swap
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);

        // swap - swapForX
        BalanceDelta delta = poolManager.swap(key, false, -1e18, "");
        assertEq(delta.amount0(), 996502000000000000);
        assertEq(delta.amount1(), -1e18);

        // // after swap, verify 0.05% fee
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0.0005 * 1e18);
    }

    function test_SwapWithProtocolFee_ExactOut_SwapForY() public {
        // Pre-req: set protocol fee at 0.1% for token0 and 0.05% for token1
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 500);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to active bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        // before swap
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);

        // swap - swapForY
        BalanceDelta delta = poolManager.swap(key, true, 1e18, "");
        assertEq(delta.amount0(), -1004013040121365097);
        assertEq(delta.amount1(), 1e18);

        // after swap, verify 0.01% fee
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 1004013040121365);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_SwapWithProtocolFee_ExactIn_SwapForY_MultipleBin() public {
        // Pre-req: set protocol fee at 0.1% for token0 and 0.05% for token1
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 500);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add liquidity to multiple bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        // before swap
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);

        // swap - swapForY
        BalanceDelta delta = poolManager.swap(key, true, -1e18, "");
        assertEq(delta.amount0(), -1e18);
        assertEq(delta.amount1(), 991567178657847266);

        // after swap, verify close to 0.1% fee
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 999999999999995);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_revert_SwapAmountSpecifiedIsZero() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 0;

        vm.expectRevert(IBinPoolManager.AmountSpecifiedIsZero.selector);
        poolManager.swap(key, true, -int128(amountIn), "0x");

        vm.expectRevert(IBinPoolManager.AmountSpecifiedIsZero.selector);
        poolManager.swap(key, false, -int128(amountIn), "0x");
    }

    function test_revert_SwapInsufficientAmountOut() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 1;

        vm.expectRevert(BinPool.BinPool__InsufficientAmountUnSpecified.selector);
        poolManager.swap(key, true, -int128(amountIn), "0x");

        vm.expectRevert(BinPool.BinPool__InsufficientAmountUnSpecified.selector);
        poolManager.swap(key, false, -int128(amountIn), "0x");
    }

    function test_revert_SwapOutOfLiquidity() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // pool only have 1e18 token0, 1e18 token1
        uint128 amountIn = 2e18;

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, true, -int128(amountIn), "0x");

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, false, -int128(amountIn), "0x");
    }

    function _getSwapFee(uint24 fee0, uint24 fee1) internal pure returns (uint24) {
        return fee0 + (fee1 << 12);
    }
}
