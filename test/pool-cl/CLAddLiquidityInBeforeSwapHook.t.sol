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
import {CLAddLiquidityInBeforeSwapHook} from "./helpers/CLAddLiquidityInBeforeSwapHook.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {console2} from "forge-std/console2.sol";

contract CLAddLiquidityInBeforeSwapHookTest is Test, Deployers, TokenFixture, GasSnapshot {
    using CLPoolParametersHelper for bytes32;
    using LPFeeLibrary for uint24;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    CLAddLiquidityInBeforeSwapHook public clDeltaHook;

    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();

        router = new CLPoolManagerRouter(vault, poolManager);
        clDeltaHook = new CLAddLiquidityInBeforeSwapHook();
        clDeltaHook.setManager(poolManager);

        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 100000000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 100000000 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(clDeltaHook), 100000000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(clDeltaHook), 100000000 ether);

        token0.mint(address(clDeltaHook), 100000000 ether);
        token1.mint(address(clDeltaHook), 1010000000000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: clDeltaHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(clDeltaHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function testSwap_AddLiquidityInHook_WillUpdateReserveOfApp() external {
        int256 liquidityDelta = 10000 ether;
        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        assertEq(liquidityBefore, 0);

        uint256 currency0AmtHookBefore = currency0.balanceOf(address(clDeltaHook));
        uint256 currency1AmtHookBefore = currency1.balanceOf(address(clDeltaHook));

        uint256 currency0AmtReserveOfAPPBefore = vault.reservesOfApp(address(poolManager), currency0);
        uint256 currency1AmtReserveOfAPPBefore = vault.reservesOfApp(address(poolManager), currency1);

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            // double the swap amt
            abi.encode(liquidityDelta)
        );

        uint256 vaultTokenBalance = vault.balanceOf(address(clDeltaHook), currency0);
        assertEq(vaultTokenBalance, 1 ether);

        uint256 currency0AmtReserveOfAPPAfter = vault.reservesOfApp(address(poolManager), currency0);
        uint256 currency1AmtReserveOfAPPAfter = vault.reservesOfApp(address(poolManager), currency1);

        uint256 currency0AmtHookAfter = currency0.balanceOf(address(clDeltaHook));
        uint256 currency1AmtHookAfter = currency1.balanceOf(address(clDeltaHook));

        uint256 currency0PayFromHook = currency0AmtHookBefore - currency0AmtHookAfter;
        uint256 currency1PayFromHook = currency1AmtHookBefore - currency1AmtHookAfter;

        console2.log("currency0PayFromHook:", currency0PayFromHook);
        console2.log("currency1PayFromHook:", currency1PayFromHook);

        uint256 reserveOfAppCurrency0Delta = currency0AmtReserveOfAPPAfter - currency0AmtReserveOfAPPBefore;
        uint256 reserveOfAppCurrency1Delta = currency1AmtReserveOfAPPAfter - currency1AmtReserveOfAPPBefore;
        console2.log("reserveOfAppCurrency0Delta:", reserveOfAppCurrency0Delta);
        console2.log("reserveOfAppCurrency1Delta:", reserveOfAppCurrency1Delta);

        assertEq(reserveOfAppCurrency0Delta, currency0PayFromHook);
        assertEq(reserveOfAppCurrency1Delta, currency1PayFromHook);

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        assertEq(liquidityAfter, uint256(liquidityDelta));
    }

    function testFuzz_Swap_AddLiquidityInHook_WillUpdateReserveOfApp(uint256 liquidityDeltaAmount, uint256 swapAmount)
        external
    {
        vm.assume(liquidityDeltaAmount < 1000000 ether && swapAmount < 1000 ether && swapAmount > 0);
        int256 liquidityDelta = int256(liquidityDeltaAmount);
        int256 amountSpecified = -int256(swapAmount);
        uint256 amt0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityBefore = poolManager.getLiquidity(key.toId());

        assertEq(liquidityBefore, 0);

        uint256 currency0AmtHookBefore = currency0.balanceOf(address(clDeltaHook));
        uint256 currency1AmtHookBefore = currency1.balanceOf(address(clDeltaHook));

        uint256 currency0AmtReserveOfAPPBefore = vault.reservesOfApp(address(poolManager), currency0);
        uint256 currency1AmtReserveOfAPPBefore = vault.reservesOfApp(address(poolManager), currency1);

        (BalanceDelta delta) = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            // double the swap amt
            abi.encode(liquidityDelta)
        );

        uint256 vaultTokenBalance = vault.balanceOf(address(clDeltaHook), currency0);
        assertEq(vaultTokenBalance, swapAmount);

        uint256 currency0AmtReserveOfAPPAfter = vault.reservesOfApp(address(poolManager), currency0);
        uint256 currency1AmtReserveOfAPPAfter = vault.reservesOfApp(address(poolManager), currency1);

        uint256 currency0AmtHookAfter = currency0.balanceOf(address(clDeltaHook));
        uint256 currency1AmtHookAfter = currency1.balanceOf(address(clDeltaHook));

        uint256 currency0PayFromHook = currency0AmtHookBefore - currency0AmtHookAfter;
        uint256 currency1PayFromHook = currency1AmtHookBefore - currency1AmtHookAfter;

        console2.log("currency0PayFromHook:", currency0PayFromHook);
        console2.log("currency1PayFromHook:", currency1PayFromHook);

        uint256 reserveOfAppCurrency0Delta = currency0AmtReserveOfAPPAfter - currency0AmtReserveOfAPPBefore;
        uint256 reserveOfAppCurrency1Delta = currency1AmtReserveOfAPPAfter - currency1AmtReserveOfAPPBefore;
        console2.log("reserveOfAppCurrency0Delta:", reserveOfAppCurrency0Delta);
        console2.log("reserveOfAppCurrency1Delta:", reserveOfAppCurrency1Delta);

        assertEq(reserveOfAppCurrency0Delta, currency0PayFromHook);
        assertEq(reserveOfAppCurrency1Delta, currency1PayFromHook);

        uint256 amt0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(vault));
        uint256 amt1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(vault));
        uint128 liquidityAfter = poolManager.getLiquidity(key.toId());

        assertEq(liquidityAfter, uint256(liquidityDelta));
    }
}
