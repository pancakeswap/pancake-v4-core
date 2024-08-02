// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Currency} from "../../src/types/Currency.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IERC20Minimal} from "../../src/interfaces/IERC20Minimal.sol";

/// @notice Helper library for currency settlement
/// @dev It is advised to consider referencing this library for currency settlement
library CurrencySettlement {
    /// @notice Settle (pay) a currency to vault
    /// @param currency Currency to settle
    /// @param vault Vault address
    /// @param payer Address of the payer, the token sender
    /// @param amount Amount to send
    /// @param burn If true, burn the VaultToken obtained by vault.mint() earlier, otherwise ERC20-transfer to vault
    function settle(Currency currency, IVault vault, address payer, uint256 amount, bool burn) internal {
        // for native currencies or burns, calling sync is not required
        if (burn) {
            vault.burn(payer, currency, amount);
        } else if (currency.isNative()) {
            vault.settle{value: amount}();
        } else {
            vault.sync(currency);
            if (payer != address(this)) {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(vault), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(vault), amount);
            }
            vault.settle();
        }
    }

    /// @notice Take (receive) a currency from vault
    /// @param currency Currency to take
    /// @param vault Vault address
    /// @param recipient Address of the recipient, the token receiver
    /// @param amount Amount to receive
    /// @param claims If true, mint VaultToken, otherwise ERC20-transfer from the vault to recipient
    function take(Currency currency, IVault vault, address recipient, uint256 amount, bool claims) internal {
        claims ? vault.mint(recipient, currency, amount) : vault.take(currency, recipient, amount);
    }
}
