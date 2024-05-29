// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../../../src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";

contract CLReturnsDeltaHook is BaseCLTestHook {
    error InvalidAction();

    using CurrencyLibrary for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;

    constructor(IVault _vault, ICLPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                befreSwapReturnsDelta: true,
                afterSwapReturnsDelta: true,
                afterAddLiquidityReturnsDelta: true,
                afterRemoveLiquidityReturnsDelta: true
            })
        );
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        BalanceDelta,
        bytes calldata data
    ) external override returns (bytes4, BalanceDelta) {
        (int256 liquidityDelta) = abi.decode(data, (int256));
        if (liquidityDelta == 0) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        params.liquidityDelta = liquidityDelta;
        (BalanceDelta delta,) = poolManager.modifyLiquidity(key, params, new bytes(0));
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA - delta);
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        BalanceDelta,
        bytes calldata data
    ) external override returns (bytes4, BalanceDelta) {
        (int256 liquidityDelta) = abi.decode(data, (int256));
        if (liquidityDelta == 0) {
            return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        params.liquidityDelta = liquidityDelta;
        (BalanceDelta delta,) = poolManager.modifyLiquidity(key, params, new bytes(0));
        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA - delta);
    }

    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata params, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (int128 hookDeltaSpecified, int128 hookDeltaUnspecified,) = abi.decode(data, (int128, int128, int128));

        if (params.zeroForOne == params.amountSpecified < 0) {
            // the specified token is token0
            if (hookDeltaSpecified < 0) {
                vault.sync(key.currency0);
                key.currency0.transfer(address(vault), uint128(-hookDeltaSpecified));
                vault.settle(key.currency0);
            } else {
                vault.take(key.currency0, address(this), uint128(hookDeltaSpecified));
            }

            if (hookDeltaUnspecified < 0) {
                vault.sync(key.currency1);
                key.currency1.transfer(address(vault), uint128(-hookDeltaUnspecified));
                vault.settle(key.currency1);
            } else {
                vault.take(key.currency1, address(this), uint128(hookDeltaUnspecified));
            }
        } else {
            // the specified token is token1
            if (hookDeltaSpecified < 0) {
                vault.sync(key.currency1);
                key.currency1.transfer(address(vault), uint128(-hookDeltaSpecified));
                vault.settle(key.currency1);
            } else {
                vault.take(key.currency1, address(this), uint128(hookDeltaSpecified));
            }

            if (hookDeltaUnspecified < 0) {
                vault.sync(key.currency0);
                key.currency0.transfer(address(vault), uint128(-hookDeltaUnspecified));
                vault.settle(key.currency0);
            } else {
                vault.take(key.currency0, address(this), uint128(hookDeltaUnspecified));
            }
        }
        return (this.beforeSwap.selector, toBeforeSwapDelta(hookDeltaSpecified, hookDeltaUnspecified), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        ICLPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata data
    ) external override returns (bytes4, int128) {
        (,, int128 hookDeltaUnspecified) = abi.decode(data, (int128, int128, int128));

        if (hookDeltaUnspecified == 0) {
            return (this.afterSwap.selector, 0);
        }

        if (params.zeroForOne == params.amountSpecified < 0) {
            // the unspecified token is token1
            if (hookDeltaUnspecified < 0) {
                vault.sync(key.currency1);
                key.currency1.transfer(address(vault), uint128(-hookDeltaUnspecified));
                vault.settle(key.currency1);
            } else {
                vault.take(key.currency1, address(this), uint128(hookDeltaUnspecified));
            }
        } else {
            // the unspecified token is token0
            if (hookDeltaUnspecified < 0) {
                vault.sync(key.currency0);
                key.currency0.transfer(address(vault), uint128(-hookDeltaUnspecified));
                vault.settle(key.currency0);
            } else {
                vault.take(key.currency0, address(this), uint128(hookDeltaUnspecified));
            }
        }

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }
}
