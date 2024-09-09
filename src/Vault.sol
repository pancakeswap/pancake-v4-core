// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault, IVaultToken} from "./interfaces/IVault.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {SettlementGuard} from "./libraries/SettlementGuard.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {ILockCallback} from "./interfaces/ILockCallback.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {VaultReserve} from "./libraries/VaultReserve.sol";
import {VaultToken} from "./VaultToken.sol";

contract Vault is IVault, VaultToken, Ownable {
    using SafeCast for *;
    using CurrencyLibrary for Currency;

    constructor() Ownable(msg.sender) {}

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
    /// @dev This function doesn't whether the caller is the poolManager specified in the PoolKey
    /// PoolManager shouldn't expect that behavior
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

    function sync(Currency currency) public override isLocked {
        VaultReserve.alreadySettledLastSync();
        if (currency.isNative()) return;
        uint256 balance = currency.balanceOfSelf();
        VaultReserve.setVaultReserve(currency, balance);
    }

    /// @inheritdoc IVault
    function settle() external payable override isLocked returns (uint256) {
        return _settle(msg.sender);
    }

    /// @inheritdoc IVault
    function settleFor(address recipient) external payable override isLocked returns (uint256) {
        return _settle(recipient);
    }

    /// @inheritdoc IVault
    function clear(Currency currency, uint256 amount) external isLocked {
        int256 existingDelta = SettlementGuard.getCurrencyDelta(msg.sender, currency);
        int128 amountDelta = amount.toInt128();
        /// @dev since amount is uint256, existingDelta must be positive otherwise revert
        if (amountDelta != existingDelta) revert MustClearExactPositiveDelta();
        unchecked {
            SettlementGuard.accountDelta(msg.sender, currency, -amountDelta);
        }
    }

    /// @inheritdoc IVault
    function burn(address from, Currency currency, uint256 amount) external override isLocked {
        SettlementGuard.accountDelta(msg.sender, currency, amount.toInt128());
        _burnFrom(from, currency, amount);
    }

    /// @inheritdoc IVault
    function collectFee(Currency currency, uint256 amount, address recipient) external onlyRegisteredApp {
        if (SettlementGuard.getLocker() != address(0)) revert LockHeld();
        reservesOfApp[msg.sender][currency] -= amount;
        currency.transfer(recipient, amount);
    }

    /// @inheritdoc IVault
    function getVaultReserve() external view returns (Currency, uint256) {
        return VaultReserve.getVaultReserve();
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

    function _settle(address recipient) internal returns (uint256 paid) {
        (Currency currency, uint256 reservesBefore) = VaultReserve.getVaultReserve();
        if (!currency.isNative()) {
            if (msg.value > 0) revert SettleNonNativeCurrencyWithValue();
            uint256 reservesNow = currency.balanceOfSelf();
            paid = reservesNow - reservesBefore;

            /// @dev reset the reserve after settled otherwise next sync() call will throw LastSyncNotSettled
            VaultReserve.setVaultReserve(CurrencyLibrary.NATIVE, 0);
        } else {
            // NATIVE token does not require sync call before settle
            paid = msg.value;
        }

        SettlementGuard.accountDelta(recipient, currency, paid.toInt128());
    }
}
