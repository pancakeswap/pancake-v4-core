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
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {SwapFeeLibrary} from "../../src/libraries/SwapFeeLibrary.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {ParametersHelper} from "../../src/libraries/math/ParametersHelper.sol";
import {CLSkipCallbackHook} from "./helpers/CLSkipCallbackHook.sol";

contract CLHookSkipCallbackTest is Test, Deployers, TokenFixture, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CLPoolParametersHelper for bytes32;
    using ParametersHelper for bytes32;
    using SwapFeeLibrary for uint24;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    // hook with all callback registered
    CLSkipCallbackHook public clSkipCallbackHook;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();

        router = new CLPoolManagerRouter(vault, poolManager);
        clSkipCallbackHook = new CLSkipCallbackHook(vault, poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(clSkipCallbackHook), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(clSkipCallbackHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: clSkipCallbackHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(clSkipCallbackHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
    }

    function testInitialize_FromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));
        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testInitialize_NotFromHook() external {
        poolManager.initialize(key, SQRT_RATIO_1_1, new bytes(0));
        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 2);
    }

    function testModifyPosition_FromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Add and remove liquidity
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: -1e18}), ""
        );
        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testModifyPosition_NotFromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Add and remove liquidity
        router.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );
        router.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: -1e18}), ""
        );
        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 4);
    }

    function testSwap_FromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Pre-req add some liqudiity
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );

        clSkipCallbackHook.swap(
            key,
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 1000, sqrtPriceLimitX96: SQRT_RATIO_1_2}),
            CLSkipCallbackHook.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );

        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testSwap_NotFromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Pre-req add some liqudiity
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );

        router.swap(
            key,
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 1000, sqrtPriceLimitX96: SQRT_RATIO_1_2}),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );

        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 2);
    }

    function testDonate_FromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Pre-req add some liqudiity
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );

        clSkipCallbackHook.donate(key, 100, 200, ZERO_BYTES);

        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testDonate_NotFromHook() external {
        clSkipCallbackHook.initialize(key, SQRT_RATIO_1_1, new bytes(0));

        // Pre-req add some liqudiity
        clSkipCallbackHook.modifyPosition(
            key, ICLPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 1e18}), ""
        );

        router.donate(key, 100, 200, ZERO_BYTES);

        assertEq(clSkipCallbackHook.hookCounterCallbackCount(), 2);
    }
}
