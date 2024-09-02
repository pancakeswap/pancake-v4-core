// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";

/// @notice This is a workaround when transient keyword is absent.
/// It records a single reserve for a currency each time, this is helpful for
/// calculating how many tokens has been transferred to the vault right after the sync
library VaultReserve {
    /// @notice Thrown when trying to sync a reserve when last sync is not settled
    error LastSyncNotSettled();

    // uint256 constant RESERVE_TYPE_SLOT = uint256(keccak256("reserveType")) - 1;
    uint256 internal constant RESERVE_TYPE_SLOT = 0x52a1be34b47478d7c75e2b6c3eea1e05dcb8dbb8c6a42c6482d0dca0df53cb27;

    // uint256 constant RESERVE_AMOUNT_SLOT = uint256(keccak256("reserveAmount")) - 1;
    uint256 internal constant RESERVE_AMOUNT_SLOT = 0xb0879d96d58bcff08d1fd45590200072d5a8c380da0b5aa1052b48b84e115207;

    function alreadySettledLastSync() internal view {
        Currency currency;
        assembly ("memory-safe") {
            currency := tload(RESERVE_TYPE_SLOT)
        }

        if (!currency.isNative()) revert LastSyncNotSettled();
    }

    /// @notice Transient store the currency reserve
    /// @param currency The currency to be saved
    /// @param amount The amount of the currency to be saved
    function setVaultReserve(Currency currency, uint256 amount) internal {
        assembly ("memory-safe") {
            // record <currency, amount> in transient storage
            tstore(RESERVE_TYPE_SLOT, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            tstore(RESERVE_AMOUNT_SLOT, amount)
        }
    }

    /// @notice Transient load the currency reserve
    /// @return currency The currency that was most recently saved
    /// @return amount The amount of the currency that was most recently saved
    function getVaultReserve() internal view returns (Currency currency, uint256 amount) {
        assembly ("memory-safe") {
            currency := tload(RESERVE_TYPE_SLOT)
            amount := tload(RESERVE_AMOUNT_SLOT)
        }
    }
}
