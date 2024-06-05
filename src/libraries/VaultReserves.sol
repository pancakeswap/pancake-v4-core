// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";

/// @notice This is a workaround when transient keyword is absent. It manages:
///  - 0: mapping(currency => uint256) reserveOfVault
library VaultReserves {
    /// @notice Thrown when getVaultReserves is called before sync
    error ReserveNotSync();

    // uint256 constant RESERVE_OF_VAULT_SLOT = uint256(keccak256("reservesOfVault")) - 1;
    uint256 constant RESERVE_OF_VAULT_SLOT = 0xb54c65c0f448723e3496562a0e878a1341c4dd2511ef542b5fd5f19cebc47663;

    /// @notice Set balance to the max as a sentinel to track that it has been set if amount == 0
    uint256 constant ZERO_BALANCE = type(uint256).max;

    /// @notice Transient store the currency reserve
    /// @dev if the amount is 0, the value stored would be ZERO_BALANCE, a sentinel value
    function setVaultReserves(Currency currency, uint256 amount) internal {
        if (amount == 0) amount = ZERO_BALANCE;

        bytes32 slotKey = _getCurrencySlotKey(currency);
        assembly ("memory-safe") {
            tstore(slotKey, amount)
        }
    }

    /// @notice Transient load the currency reserve
    /// @dev If this is called before vault.sync, it will be reverted
    function getVaultReserves(Currency currency) internal view returns (uint256 amount) {
        bytes32 slotKey = _getCurrencySlotKey(currency);
        assembly ("memory-safe") {
            amount := tload(slotKey)
        }

        if (amount == 0) revert ReserveNotSync();
        if (amount == ZERO_BALANCE) return 0;
    }

    function _getCurrencySlotKey(Currency currency) internal pure returns (bytes32 key) {
        assembly ("memory-safe") {
            mstore(0x0, RESERVE_OF_VAULT_SLOT)
            mstore(0x20, currency)
            key := keccak256(0x0, 0x40)
        }
    }
}
