// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import "../interfaces/IBinHooks.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {IBinPoolManager} from "../interfaces/IBinPoolManager.sol";
import {Hooks} from "../../libraries/Hooks.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";
import {ParseBytes} from "../../libraries/ParseBytes.sol";
import {SafeCast} from "../../libraries/SafeCast.sol";
import {Hooks} from "../../libraries/Hooks.sol";

library BinHooks {
    using Hooks for bytes32;
    using SafeCast for int256;
    using LPFeeLibrary for uint24;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using ParseBytes for bytes;

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

    function beforeInitialize(PoolKey memory key, uint24 activeId, bytes calldata hookData) internal {
        IBinHooks hooks = IBinHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_BEFORE_INITIALIZE_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.beforeInitialize, (msg.sender, key, activeId, hookData)));
        }
    }

    function afterInitialize(PoolKey memory key, uint24 activeId, bytes calldata hookData) internal {
        IBinHooks hooks = IBinHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_AFTER_INITIALIZE_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.afterInitialize, (msg.sender, key, activeId, hookData)));
        }
    }

    function beforeMint(PoolKey memory key, IBinPoolManager.MintParams calldata params, bytes calldata hookData)
        internal
    {
        IBinHooks hooks = IBinHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_BEFORE_MINT_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.beforeMint, (msg.sender, key, params, hookData)));
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
            hookDelta = BalanceDelta.wrap(
                Hooks.callHookWithReturnDelta(
                    hooks,
                    abi.encodeCall(IBinHooks.afterMint, (msg.sender, key, params, delta, hookData)),
                    key.parameters.hasOffsetEnabled(HOOKS_AFTER_MINT_RETURNS_DELTA_OFFSET)
                )
            );

            callerDelta = callerDelta - hookDelta;
        }
    }

    function beforeBurn(PoolKey memory key, IBinPoolManager.BurnParams memory params, bytes calldata hookData)
        internal
    {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        if (key.parameters.shouldCall(HOOKS_BEFORE_BURN_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.beforeBurn, (msg.sender, key, params, hookData)));
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
            hookDelta = BalanceDelta.wrap(
                Hooks.callHookWithReturnDelta(
                    hooks,
                    abi.encodeCall(IBinHooks.afterBurn, (msg.sender, key, params, delta, hookData)),
                    key.parameters.hasOffsetEnabled(HOOKS_AFTER_BURN_RETURNS_DELTA_OFFSET)
                )
            );

            callerDelta = callerDelta - hookDelta;
        }
    }

    function beforeSwap(PoolKey memory key, bool swapForY, int128 amountSpecified, bytes calldata hookData)
        internal
        returns (int128 amountToSwap, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride)
    {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        amountToSwap = amountSpecified;

        /// @notice If the hook is not registered, return the original amount to swap
        if (!key.parameters.shouldCall(HOOKS_BEFORE_SWAP_OFFSET, hooks)) {
            return (amountToSwap, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFeeOverride);
        }

        bytes memory result = Hooks.callHook(
            hooks, abi.encodeCall(IBinHooks.beforeSwap, (msg.sender, key, swapForY, amountSpecified, hookData))
        );

        // A length of 96 bytes is required to return a bytes4, a 32 byte delta, and an LP fee
        if (result.length != 96) revert Hooks.InvalidHookResponse();

        if (key.fee.isDynamicLPFee()) {
            lpFeeOverride = result.parseFee();
        }

        // Update the swap amount according to the hook's return
        if (key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET)) {
            // any return in unspecified is passed to the afterSwap hook for handling
            beforeSwapDelta = BeforeSwapDelta.wrap(result.parseReturnDelta());
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
        bool swapForY,
        int128 amountSpecified,
        BalanceDelta delta,
        bytes calldata hookData,
        BeforeSwapDelta beforeSwapDelta
    ) internal returns (BalanceDelta, BalanceDelta) {
        IBinHooks hooks = IBinHooks(address(key.hooks));

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified = beforeSwapDelta.getUnspecifiedDelta();
        if (key.parameters.shouldCall(HOOKS_AFTER_SWAP_OFFSET, hooks)) {
            hookDeltaUnspecified += Hooks.callHookWithReturnDelta(
                hooks,
                abi.encodeCall(IBinHooks.afterSwap, (msg.sender, key, swapForY, amountSpecified, delta, hookData)),
                key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)
            ).toInt128();
        }

        BalanceDelta hookDelta;
        if (hookDeltaUnspecified != 0 || hookDeltaSpecified != 0) {
            hookDelta = (amountSpecified < 0 == swapForY)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);

            // the caller has to pay for (or receive) the hook's delta
            delta = delta - hookDelta;
        }

        return (delta, hookDelta);
    }

    function beforeDonate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookData) internal {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        if (key.parameters.shouldCall(HOOKS_BEFORE_DONATE_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.beforeDonate, (msg.sender, key, amount0, amount1, hookData)));
        }
    }

    function afterDonate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookData) internal {
        IBinHooks hooks = IBinHooks(address(key.hooks));
        if (key.parameters.shouldCall(HOOKS_AFTER_DONATE_OFFSET, hooks)) {
            Hooks.callHook(hooks, abi.encodeCall(IBinHooks.afterDonate, (msg.sender, key, amount0, amount1, hookData)));
        }
    }
}
