// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault, IVaultToken} from "./interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {SettlementGuard} from "./libraries/SettlementGuard.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {ILockCallback} from "./interfaces/ILockCallback.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {VaultReserves} from "./libraries/VaultReserves.sol";
import {VaultToken} from "./VaultToken.sol";

contract Vault is IVault, VaultToken, Ownable {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using VaultReserves for Currency;

    mapping(address app => bool isRegistered) public override isAppRegistered;

    /// @dev keep track of each app's reserves
    mapping(address app => mapping(Currency currency => uint256 reserve)) public reservesOfApp;

    /// @notice only registered app is allowed to perform accounting
    modifier onlyRegisteredApp() {
        if (!isAppRegistered[msg.sender]) revert AppUnregistered();

        _;
    }

    /// @notice revert if no locker is set
    modifier isLocked() {
        if (SettlementGuard.getLocker() == address(0)) revert NoLocker();
        _;
    }

    /// @inheritdoc IVault
    function registerApp(address app) external override onlyOwner {
        isAppRegistered[app] = true;

        emit AppRegistered(app);
    }

    /// @inheritdoc IVault
    function getLocker() external view override returns (address) {
        return SettlementGuard.getLocker();
    }

    /// @inheritdoc IVault
    function getUnsettledDeltasCount() external view override returns (uint256) {
        return SettlementGuard.getUnsettledDeltasCount();
    }

    /// @inheritdoc IVault
    function currencyDelta(address settler, Currency currency) external view override returns (int256) {
        return SettlementGuard.getCurrencyDelta(settler, currency);
    }

    /// @dev interaction must start from lock
    /// @inheritdoc IVault
    function lock(bytes calldata data) external override returns (bytes memory result) {
        /// @dev only one locker at a time
        SettlementGuard.setLocker(msg.sender);

        result = ILockCallback(msg.sender).lockAcquired(data);
        /// @notice the caller can do anything in this callback as long as all deltas are offset after this
        if (SettlementGuard.getUnsettledDeltasCount() != 0) revert CurrencyNotSettled();

        /// @dev release the lock
        SettlementGuard.setLocker(address(0));
    }

    /// @inheritdoc IVault
    function accountAppBalanceDelta(PoolKey memory key, BalanceDelta delta, address settler)
        external
        override
        isLocked
        onlyRegisteredApp
    {
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        // keep track of the balance on app level
        _accountDeltaForApp(msg.sender, key.currency0, delta0);
        _accountDeltaForApp(msg.sender, key.currency1, delta1);

        // keep track of the balance on vault level
        SettlementGuard.accountDelta(settler, key.currency0, delta0);
        SettlementGuard.accountDelta(settler, key.currency1, delta1);
    }

    /// @inheritdoc IVault
    function accountAppBalanceDelta(Currency currency, int128 delta, address settler)
        external
        override
        isLocked
        onlyRegisteredApp
    {
        _accountDeltaForApp(msg.sender, currency, delta);
        SettlementGuard.accountDelta(settler, currency, delta);
    }

    /// @inheritdoc IVault
    function take(Currency currency, address to, uint256 amount) external override isLocked {
        unchecked {
            SettlementGuard.accountDelta(msg.sender, currency, -(amount.toInt128()));
            currency.transfer(to, amount);
        }
    }

    /// @inheritdoc IVault
    function mint(address to, Currency currency, uint256 amount) external override isLocked {
        unchecked {
            SettlementGuard.accountDelta(msg.sender, currency, -(amount.toInt128()));
            _mint(to, currency, amount);
        }
    }

    function sync(Currency currency) public returns (uint256 balance) {
        balance = currency.balanceOfSelf();
        currency.setVaultReserves(balance);
    }

    /// @inheritdoc IVault
    function settle(Currency currency) external payable override isLocked returns (uint256 paid) {
        if (!currency.isNative()) {
            if (msg.value > 0) revert SettleNonNativeCurrencyWithValue();
            uint256 reservesBefore = currency.getVaultReserves();
            uint256 reservesNow = sync(currency);
            paid = reservesNow - reservesBefore;
        } else {
            paid = msg.value;
        }

        SettlementGuard.accountDelta(msg.sender, currency, paid.toInt128());
    }

    /// @inheritdoc IVault
    function burn(address from, Currency currency, uint256 amount) external override isLocked {
        SettlementGuard.accountDelta(msg.sender, currency, amount.toInt128());
        _burnFrom(from, currency, amount);
    }

    /// @inheritdoc IVault
    function collectFee(Currency currency, uint256 amount, address recipient) external onlyRegisteredApp {
        reservesOfApp[msg.sender][currency] -= amount;
        currency.transfer(recipient, amount);
    }

    /// @inheritdoc IVault
    function reservesOfVault(Currency currency) external view returns (uint256) {
        return currency.getVaultReserves();
    }

    function _accountDeltaForApp(address app, Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            /// @dev arithmetic underflow make sure trader can't withdraw too much from app
            reservesOfApp[app][currency] -= uint128(delta);
        } else {
            /// @dev arithmetic overflow make sure trader won't deposit too much into app
            reservesOfApp[app][currency] += uint128(-delta);
        }
    }
}
