// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import "../interfaces/IBinHooks.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {IBinPoolManager} from "../interfaces/IBinPoolManager.sol";
import {Hooks} from "../../libraries/Hooks.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";

library BinHooks {
    using Hooks for bytes32;
    using LPFeeLibrary for uint24;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

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
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_MINT_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_MINT_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_BURN_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_BURN_OFFSET)
        ) {
            revert Hooks.HookPermissionsValidationError();
        }
    }

    function afterMint(
        PoolKey memory key,
        IBinPoolManager.MintParams memory params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal returns (BalanceDelta callerDelta, BalanceDelta hookDelta) {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        callerDelta = delta;

        if (key.parameters.shouldCall(HOOKS_AFTER_MINT_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDelta) = hooks.afterMint(msg.sender, key, params, delta, hookData);

            if (selector != IBinHooks.afterMint.selector) {
                revert Hooks.InvalidHookResponse();
            }

            if (
                key.parameters.hasOffsetEnabled(HOOKS_AFTER_MINT_RETURNS_DELTA_OFFSET)
                    && hookDelta != BalanceDeltaLibrary.ZERO_DELTA
            ) {
                callerDelta = callerDelta - hookDelta;
            }
        }
    }

    function afterBurn(
        PoolKey memory key,
        IBinPoolManager.BurnParams memory params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal returns (BalanceDelta callerDelta, BalanceDelta hookDelta) {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        callerDelta = delta;

        if (key.parameters.shouldCall(HOOKS_AFTER_BURN_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDelta) = hooks.afterBurn(msg.sender, key, params, delta, hookData);

            if (selector != IBinHooks.afterBurn.selector) {
                revert Hooks.InvalidHookResponse();
            }

            if (
                key.parameters.hasOffsetEnabled(HOOKS_AFTER_BURN_RETURNS_DELTA_OFFSET)
                    && hookDelta != BalanceDeltaLibrary.ZERO_DELTA
            ) {
                callerDelta = callerDelta - hookDelta;
            }
        }
    }

    function beforeSwap(PoolKey memory key, bool swapForY, uint128 amountIn, bytes calldata hookData)
        internal
        returns (uint128 amountToSwap, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride)
    {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        amountToSwap = amountIn;

        /// @notice If the hook is not registered, return the original amount to swap
        if (!key.parameters.shouldCall(HOOKS_BEFORE_SWAP_OFFSET, hooks)) {
            return (amountToSwap, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFeeOverride);
        }

        bytes4 selector;
        (selector, beforeSwapDelta, lpFeeOverride) = hooks.beforeSwap(msg.sender, key, swapForY, amountIn, hookData);
        if (selector != IBinHooks.beforeSwap.selector) {
            revert Hooks.InvalidHookResponse();
        }

        if (!key.fee.isDynamicLPFee()) {
            lpFeeOverride = 0;
        }

        // Update the swap amount according to the hook's return
        if (key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET)) {
            // any return in unspecified is passed to the afterSwap hook for handling
            int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();

            if (hookDeltaSpecified != 0) {
                /// @dev default overflow check make sure the swap amount is always valid
                if (hookDeltaSpecified > 0) {
                    amountToSwap += uint128(hookDeltaSpecified);
                } else {
                    amountToSwap -= uint128(-hookDeltaSpecified);
                }
            }
        }
    }

    function afterSwap(
        PoolKey memory key,
        bool swapForY,
        uint128 amountIn,
        BalanceDelta delta,
        bytes calldata hookData,
        BeforeSwapDelta beforeSwapDelta
    ) internal returns (BalanceDelta swapperDelta, BalanceDelta hookDelta) {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        swapperDelta = delta;

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified;
        if (key.parameters.shouldCall(HOOKS_AFTER_SWAP_OFFSET, hooks)) {
            bytes4 selector;
            (selector, hookDeltaUnspecified) = hooks.afterSwap(msg.sender, key, swapForY, amountIn, delta, hookData);
            if (selector != IBinHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }

            // TODO: Potentially optimization: skip decoding the second return value when afterSwapReturnDelta not set
            if (!key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)) {
                hookDeltaUnspecified = 0;
            }
        }
        hookDeltaUnspecified += beforeSwapDelta.getUnspecifiedDelta();

        if (hookDeltaUnspecified != 0 || hookDeltaSpecified != 0) {
            hookDelta = swapForY
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);

            // the caller has to pay for (or receive) the hook's delta
            swapperDelta = delta - hookDelta;
        }
    }
}
