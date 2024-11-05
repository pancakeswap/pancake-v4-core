// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @notice Library for handling AppDeltaSettlement for the apps (eg. CL, Bin etc..)
library VaultAppDeltaSettlement {
    /// @notice helper method to call `vault.accountAppBalanceDelta`
    /// @dev Vault maintains a `reserveOfApp` to protect against exploits in one app from accessing funds in another.
    /// To prevent underflow in `reserveOfApp`, it is essential to handle `appDelta` and `hookDelta` in a specific order.
    function accountAppDeltaWithHookDelta(
        IVault vault,
        PoolKey memory key,
        BalanceDelta delta,
        BalanceDelta hookDelta,
        address settler
    ) internal {
        if (hookDelta == BalanceDeltaLibrary.ZERO_DELTA) {
            /// @dev default case when no hook return delta is set
            vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, settler);
        } else {
            /// @dev if hookDelta is not 0, call vault.accountAppBalanceDelta with negative delta first
            /// negative delta means user/hook owes vault money, so reservesOfApp in vault will not underflow
            (int128 hookDelta0, int128 hookDelta1) = (hookDelta.amount0(), hookDelta.amount1());
            (int128 delta0, int128 delta1) = (delta.amount0(), delta.amount1());

            if (hookDelta0 < 0) {
                vault.accountAppBalanceDelta(key.currency0, hookDelta0, address(key.hooks));
                if (delta0 != 0) vault.accountAppBalanceDelta(key.currency0, delta0, settler);
            } else {
                if (delta0 != 0) vault.accountAppBalanceDelta(key.currency0, delta0, settler);
                if (hookDelta0 != 0) vault.accountAppBalanceDelta(key.currency0, hookDelta0, address(key.hooks));
            }

            if (hookDelta1 < 0) {
                vault.accountAppBalanceDelta(key.currency1, hookDelta1, address(key.hooks));
                if (delta1 != 0) vault.accountAppBalanceDelta(key.currency1, delta1, settler);
            } else {
                if (delta1 != 0) vault.accountAppBalanceDelta(key.currency1, delta1, settler);
                if (hookDelta1 != 0) vault.accountAppBalanceDelta(key.currency1, hookDelta1, address(key.hooks));
            }
        }
    }
}
