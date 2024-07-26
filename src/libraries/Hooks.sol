// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {IHooks} from "../interfaces/IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Encoded} from "./math/Encoded.sol";
import {LPFeeLibrary} from "./LPFeeLibrary.sol";
import {ParametersHelper} from "./math/ParametersHelper.sol";
import {ParseBytes} from "./ParseBytes.sol";

library Hooks {
    using Encoded for bytes32;
    using ParametersHelper for bytes32;
    using LPFeeLibrary for uint24;
    using ParseBytes for bytes;

    /// @param revertReason bubbled up revert reason
    error FailedHookCall(bytes revertReason);

    /// @notice Hook permissions contain conflict
    ///  1. enabled beforeSwapReturnsDelta, but lacking beforeSwap call
    ///  2. enabled afterSwapReturnsDelta, but lacking afterSwap call
    ///  3. enabled addLiquidityReturnsDelta/mintReturnsDelta, but lacking addLiquidity/mint call
    ///  4. enabled removeLiquidityReturnsDelta/burnReturnsDelta, but lacking removeLiquidityburn call
    error HookPermissionsValidationError();

    /// @notice Hook config validation failed
    /// 1. either registration bitmap mismatch
    /// 2. or fee related config misconfigured

    error HookConfigValidationError();

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Hook delta exceeds swap amount
    error HookDeltaExceedsSwapAmount();

    /// @notice Utility function intended to be used in pool initialization to ensure
    /// the hook contract's hooks registration bitmap match the configration in the pool key
    function validateHookConfig(PoolKey memory poolKey) internal view {
        uint16 bitmapInParameters = poolKey.parameters.getHooksRegistrationBitmap();
        if (address(poolKey.hooks) == address(0)) {
            /// @notice If the hooks address is 0, then the bitmap must be 0,
            /// in the same time, the dynamic fee should be disabled as well
            if (bitmapInParameters == 0 && !poolKey.fee.isDynamicLPFee()) {
                return;
            }
            revert HookConfigValidationError();
        }

        if (poolKey.hooks.getHooksRegistrationBitmap() != bitmapInParameters) {
            revert HookConfigValidationError();
        }
    }

    /// @return true if parameter has offset enabled
    function hasOffsetEnabled(bytes32 parameters, uint8 offset) internal pure returns (bool) {
        return parameters.decodeBool(offset);
    }

    /// @notice checks if hook should be called -- based on 2 factors:
    /// 1. whether pool.parameters has the callback offset registered
    /// 2. whether msg.sender is the hook itself
    function shouldCall(bytes32 parameters, uint8 offset, IHooks hook) internal view returns (bool) {
        return hasOffsetEnabled(parameters, offset) && address(hook) != msg.sender;
    }

    /// @notice performs a hook call using the given calldata on the given hook that doesnt return a delta
    /// @return result The complete data returned by the hook
    function callHook(IHooks self, bytes memory data) internal returns (bytes memory result) {
        bytes4 selector = FailedHookCall.selector;
        assembly ("memory-safe") {
            // Revert with FailedHookCall, containing any error message to bubble up
            if iszero(call(gas(), self, 0, add(data, 0x20), mload(data), 0, 0)) {
                let size := returndatasize()
                let fmp := mload(0x40)

                // Encode selector, offset, size, data
                mstore(fmp, selector)
                mstore(add(fmp, 0x04), 0x20)
                mstore(add(fmp, 0x24), size)
                returndatacopy(add(fmp, 0x44), 0, size)

                // Ensure the size is a multiple of 32 bytes
                let encodedSize := add(0x44, mul(div(add(size, 31), 32), 32))
                revert(fmp, encodedSize)
            }

            // The call was successful, fetch the returned data
            // allocate result byte array from the free memory pointer
            result := mload(0x40)
            // store new free memory pointer at the end of the array padded to 32 bytes
            mstore(0x40, add(result, and(add(returndatasize(), 0x3f), not(0x1f))))
            // store length in memory
            mstore(result, returndatasize())
            // copy return data to result
            returndatacopy(add(result, 0x20), 0, returndatasize())
        }

        // Length must be at least 32 to contain the selector. Check expected selector and returned selector match.
        if (result.length < 32 || result.parseSelector() != data.parseSelector()) {
            revert InvalidHookResponse();
        }
    }

    /// @notice performs a hook call using the given calldata on the given hook
    /// @return delta The delta returned by the hook
    function callHookWithReturnDelta(IHooks self, bytes memory data, bool parseReturn)
        internal
        returns (int256 delta)
    {
        bytes memory result = callHook(self, data);

        // If this hook wasnt meant to return something, default to 0 delta
        if (!parseReturn) return 0;

        // A length of 64 bytes is required to return a bytes4, and a 32 byte delta
        if (result.length != 64) revert InvalidHookResponse();
        return result.parseReturnDelta();
    }
}
