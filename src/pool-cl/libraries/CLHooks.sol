// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import "../interfaces/ICLHooks.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {ICLPoolManager} from "../interfaces/ICLPoolManager.sol";
import {Hooks} from "../../libraries/Hooks.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../../types/BalanceDelta.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";
import {BeforeSwapDeltaLibrary, BeforeSwapDelta} from "../../types/BeforeSwapDelta.sol";

library CLHooks {
    using Hooks for bytes32;
    using LPFeeLibrary for uint24;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    /// @notice Validate hook permission, eg. if before_swap_return_delta is set, before_swap_delta must be set
    function validatePermissionsConflict(PoolKey memory key) internal pure {
        if (
            key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_ADD_LIQUIDIY_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_ADD_LIQUIDITY_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_REMOVE_LIQUIDIY_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }
    }

    function beforeInitialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData) internal {
        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_BEFORE_INITIALIZE_OFFSET, hooks)) {
            if (hooks.beforeInitialize(msg.sender, key, sqrtPriceX96, hookData) != ICLHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    function afterInitialize(PoolKey memory key, uint160 sqrtPriceX96, int24 tick, bytes calldata hookData) internal {
        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_AFTER_INITIALIZE_OFFSET, hooks)) {
            if (
                hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick, hookData)
                    != ICLHooks.afterInitialize.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    function beforeModifyLiquidity(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) internal {
        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (params.liquidityDelta > 0 && key.parameters.shouldCall(HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET, hooks)) {
            if (hooks.beforeAddLiquidity(msg.sender, key, params, hookData) != ICLHooks.beforeAddLiquidity.selector) {
                revert Hooks.InvalidHookResponse();
            }
        } else if (params.liquidityDelta <= 0 && key.parameters.shouldCall(HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET, hooks))
        {
            if (
                hooks.beforeRemoveLiquidity(msg.sender, key, params, hookData)
                    != ICLHooks.beforeRemoveLiquidity.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    function afterModifyLiquidity(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal returns (BalanceDelta callerDelta, BalanceDelta hookDelta) {
        ICLHooks hooks = ICLHooks(address(key.hooks));
        callerDelta = delta;

        if (params.liquidityDelta > 0 && key.parameters.shouldCall(HOOKS_AFTER_ADD_LIQUIDITY_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDelta) = hooks.afterAddLiquidity(msg.sender, key, params, delta, hookData);

            if (selector != ICLHooks.afterAddLiquidity.selector) {
                revert Hooks.InvalidHookResponse();
            }

            if (
                key.parameters.hasOffsetEnabled(HOOKS_AFTER_ADD_LIQUIDIY_RETURNS_DELTA_OFFSET)
                    && hookDelta != BalanceDeltaLibrary.ZERO_DELTA
            ) {
                callerDelta = callerDelta - hookDelta;
            }
        } else if (params.liquidityDelta < 0 && key.parameters.shouldCall(HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDelta) = hooks.afterRemoveLiquidity(msg.sender, key, params, delta, hookData);

            if (selector != ICLHooks.afterRemoveLiquidity.selector) {
                revert Hooks.InvalidHookResponse();
            }

            if (
                key.parameters.hasOffsetEnabled(HOOKS_AFTER_REMOVE_LIQUIDIY_RETURNS_DELTA_OFFSET)
                    && hookDelta != BalanceDeltaLibrary.ZERO_DELTA
            ) {
                callerDelta = callerDelta - hookDelta;
            }
        }
    }

    function beforeSwap(PoolKey memory key, ICLPoolManager.SwapParams memory params, bytes calldata hookData)
        internal
        returns (int256 amountToSwap, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride)
    {
        ICLHooks hooks = ICLHooks(address(key.hooks));
        amountToSwap = params.amountSpecified;

        /// @notice If the hook is not registered, return the original amount to swap
        if (!key.parameters.shouldCall(HOOKS_BEFORE_SWAP_OFFSET, hooks)) {
            return (amountToSwap, beforeSwapDelta, lpFeeOverride);
        }

        bytes4 selector;
        // TODO: Potentially optimization: skip decoding the second return value when afterSwapReturnDelta not set
        (selector, beforeSwapDelta, lpFeeOverride) = hooks.beforeSwap(msg.sender, key, params, hookData);
        if (selector != ICLHooks.beforeSwap.selector) {
            revert Hooks.InvalidHookResponse();
        }

        if (!key.fee.isDynamicLPFee()) {
            lpFeeOverride = 0;
        }

        // Update the swap amount according to the hook's return, and check that the swap type doesnt change (exact input/output)
        if (key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET)) {
            // any return in unspecified is passed to the afterSwap hook for handling
            int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();

            if (hookDeltaSpecified != 0) {
                bool exactInput = amountToSwap < 0;
                amountToSwap += hookDeltaSpecified;
                if (exactInput ? amountToSwap > 0 : amountToSwap < 0) revert Hooks.HookDeltaExceedsSwapAmount();
            }
        }
    }

    function afterSwap(
        PoolKey memory key,
        ICLPoolManager.SwapParams memory params,
        BalanceDelta delta,
        bytes calldata hookData,
        BeforeSwapDelta beforeSwapDelta
    ) internal returns (BalanceDelta swapperDelta, BalanceDelta hookDelta) {
        ICLHooks hooks = ICLHooks(address(key.hooks));
        swapperDelta = delta;

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified;
        if (key.parameters.shouldCall(HOOKS_AFTER_SWAP_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDeltaUnspecified) = hooks.afterSwap(msg.sender, key, params, delta, hookData);
            if (selector != ICLHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }

            if (!key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)) {
                hookDeltaUnspecified = 0;
            }
        }
        hookDeltaUnspecified += beforeSwapDelta.getUnspecifiedDelta();

        if (hookDeltaUnspecified != 0 || hookDeltaSpecified != 0) {
            hookDelta = (params.amountSpecified < 0 == params.zeroForOne)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);

            // the caller has to pay for (or receive) the hook's delta
            swapperDelta = delta - hookDelta;
        }
    }

    function beforeDonate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData) internal {
        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_BEFORE_DONATE_OFFSET, hooks)) {
            if (hooks.beforeDonate(msg.sender, key, amount0, amount1, hookData) != ICLHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    function afterDonate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData) internal {
        ICLHooks hooks = ICLHooks(address(key.hooks));
        if (key.parameters.shouldCall(HOOKS_AFTER_DONATE_OFFSET, hooks)) {
            if (hooks.afterDonate(msg.sender, key, amount0, amount1, hookData) != ICLHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }
}
