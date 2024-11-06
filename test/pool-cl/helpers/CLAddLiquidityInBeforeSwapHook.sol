// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {ICLHooks} from "../../../src/pool-cl/interfaces/ICLHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {console2} from "forge-std/console2.sol";

contract CLAddLiquidityInBeforeSwapHook is BaseCLTestHook {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencySettlement for Currency;

    ICLPoolManager manager;

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                befreSwapReturnsDelta: true,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function setManager(ICLPoolManager _manager) external {
        manager = _manager;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        ICLPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        int256 liquidityDelta = abi.decode(hookData, (int256));
        if (liquidityDelta > 0) {
            (BalanceDelta delta,) = manager.modifyLiquidity(
                key,
                ICLPoolManager.ModifyLiquidityParams({
                    tickLower: -100,
                    tickUpper: 100,
                    liquidityDelta: liquidityDelta,
                    salt: 0
                }),
                new bytes(0)
            );

            int128 currency0Amt = delta.amount0();
            int128 currency1Amt = delta.amount1();

            console2.log("add liquidity currency0 amount:", -currency0Amt);
            console2.log("add liquidity currency1 amount:", -currency1Amt);

            // pay amount0
            key.currency0.settle(manager.vault(), address(this), uint128(-currency0Amt), false);

            // pay amount1
            key.currency1.settle(manager.vault(), address(this), uint128(-currency1Amt), false);
        }

        // Take input currency and amount
        key.currency0.take(manager.vault(), address(this), uint256(-params.amountSpecified), true);

        return (ICLHooks.beforeSwap.selector, toBeforeSwapDelta(int128(-params.amountSpecified), 0), 0);
    }
}
