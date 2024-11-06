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
    function accountAppDeltaWithHookDelta(IVault vault, PoolKey memory key, BalanceDelta delta, BalanceDelta hookDelta)
        internal
    {
        if (hookDelta == BalanceDeltaLibrary.ZERO_DELTA) {
            /// @dev default case when no hook return delta is set
            vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, msg.sender);
        } else {
            vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, msg.sender, hookDelta, address(key.hooks));
        }
    }
}
