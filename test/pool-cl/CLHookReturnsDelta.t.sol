// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Vault} from "../../src/Vault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {CLPool} from "../../src/pool-cl/libraries/CLPool.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {CLReturnsDeltaHook} from "./helpers/CLReturnsDeltaHook.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";

contract CLHookReturnsDeltaTest is Test, Deployers, TokenFixture, GasSnapshot {
    using CLPoolParametersHelper for bytes32;
    using LPFeeLibrary for uint24;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    CLReturnsDeltaHook public clReturnsDeltaHook;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();

        router = new CLPoolManagerRouter(vault, poolManager);
        clReturnsDeltaHook = new CLReturnsDeltaHook(vault, poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(clReturnsDeltaHook), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(clReturnsDeltaHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: clReturnsDeltaHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(clReturnsDeltaHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function testModifyPosition_AddMore() external {
        (BalanceDelta delta,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(0 ether)
        );

        uint128 liquidity = poolManager.getLiquidity(key.toId());

        (BalanceDelta delta2,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(10 ether)
        );
        uint128 liquidity2 = poolManager.getLiquidity(key.toId());

        // hook double the liquidity
        assertEq(delta.amount0() * 2, delta2.amount0());
        assertEq(delta.amount1() * 2, delta2.amount1());

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), uint128(-delta.amount0()) * 3);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), uint128(-delta.amount1()) * 3);

        assertEq(liquidity * 2, liquidity2 - liquidity);
    }

    function testModifyPosition_AddLess() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(10 ether)
        );

        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());
        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        (BalanceDelta delta,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(-10 ether)
        );
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());
        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        assertEq(liquidityBefore, liquidityAfter);
        assertEq(amt0Before, amt0After - 1);
        assertEq(amt1Before, amt1After - 1);

        assertEq(delta.amount0(), -1);
        assertEq(delta.amount1(), -1);
    }

    function testModifyPosition_RemoveMore() external {
        // add some liquidity first in case the pool is empty
        (BalanceDelta delta,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(10 ether)
        );

        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());
        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        (BalanceDelta delta2,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: -5 ether, salt: 0}),
            abi.encode(-5 ether)
        );
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());
        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        assertEq(liquidityBefore, liquidityAfter * 2);
        assertEq(amt0Before, (amt0After - 1) * 2);
        assertEq(amt1Before, (amt1After - 1) * 2);

        assertEq(-delta.amount0(), (delta2.amount0() + 1) * 2);
        assertEq(-delta.amount1(), (delta2.amount1() + 1) * 2);
    }

    function testModifyPosition_RemoveLess() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10 ether, salt: 0}),
            abi.encode(10 ether)
        );

        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());
        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        (BalanceDelta delta,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: -5 ether, salt: 0}),
            abi.encode(5 ether)
        );
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());
        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));

        assertEq(liquidityBefore, liquidityAfter);
        assertEq(amt0Before, amt0After - 1);
        assertEq(amt1Before, amt1After - 1);

        assertEq(delta.amount0(), -1);
        assertEq(delta.amount1(), -1);
    }

    function testSwap_noSwap_specifyInput() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(1 ether, 0, 0)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 0);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 1 ether);

        assertEq(amt0Before, amt0After);
        assertEq(amt1Before, amt1After);
        assertEq(liquidityBefore, liquidityAfter);
    }

    function testSwap_noSwap_specifyOutput() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        // make sure hook has enough balance to pay
        currency1.transfer(address(clReturnsDeltaHook), 1 ether);

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(-1 ether, 0, 0)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // hook pays 1 ether of currency1 to user and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), 0);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 0 ether);

        assertEq(amt0Before, amt0After);
        assertEq(amt1Before, amt1After);
        assertEq(liquidityBefore, liquidityAfter);
    }

    function testSwap_noSwap_returnUnspecifiedInBeforeSwap() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        currency1.transfer(address(clReturnsDeltaHook), 1 ether);

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(1 ether, -1 ether, 0)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 1 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(clReturnsDeltaHook)), 0 ether);

        assertEq(amt0Before, amt0After);
        assertEq(amt1Before, amt1After);
        assertEq(liquidityBefore, liquidityAfter);
    }

    function testSwap_noSwap_returnUnspecifiedInBeforeSwapAndAfterSwap() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        currency1.transfer(address(clReturnsDeltaHook), 1 ether);

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(1 ether, -0.5 ether, -0.5 ether)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 1 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(clReturnsDeltaHook)), 0 ether);

        assertEq(amt0Before, amt0After);
        assertEq(amt1Before, amt1After);
        assertEq(liquidityBefore, liquidityAfter);
    }

    function testSwap_SwapMore() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        // make sure hook has enough balance to pay
        currency0.transfer(address(clReturnsDeltaHook), 1 ether);

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            // double the swap amt
            abi.encode(-1 ether, 0, 0)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertApproxEqRel(delta.amount1(), 2 ether, 1e16);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 0 ether);

        assertEq(amt0After - amt0Before, 2 ether);
        assertApproxEqRel(amt1Before - amt1After, 2 ether, 1e16);
        assertEq(liquidityBefore, liquidityAfter);
    }

    function testSwap_SwapLess() external {
        // add some liquidity first in case the pool is empty
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            abi.encode(10000 ether)
        );

        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(0.5 ether, 0, 0)
        );

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertApproxEqRel(delta.amount1(), 0.5 ether, 1e16);

        // hook's payment & return
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(clReturnsDeltaHook)), 0.5 ether);

        assertEq(amt0After - amt0Before, 0.5 ether);
        assertApproxEqRel(amt1Before - amt1After, 0.5 ether, 1e16);
        assertEq(liquidityBefore, liquidityAfter);
    }
}
