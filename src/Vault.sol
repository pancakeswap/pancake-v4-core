// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault, IVaultToken} from "./interfaces/IVault.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {SettlementGuard} from "./libraries/SettlementGuard.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {ILockCallback} from "./interfaces/ILockCallback.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {VaultReserves} from "./libraries/VaultReserves.sol";
import {VaultToken} from "./VaultToken.sol";
import {ParametersHelper} from "./libraries/math/ParametersHelper.sol";

contract Vault is IVault, VaultToken, Ownable {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using VaultReserves for Currency;
    using ParametersHelper for bytes32;

    /// @dev keep track how many manager had been registered, start from 1
    uint256 public PoolManagerLength;

    mapping(address => bool) public override isPoolManagerRegistered;

    mapping(uint256 => address) public override poolManagerId;

    /// @dev keep track of each pool manager's reserves
    mapping(IPoolManager poolManager => mapping(Currency currency => uint256 reserve)) public reservesOfPoolManager;

    /// @notice only poolManager is allowed to call swap or modifyLiquidity, donate
    /// @param parameters The address specified in PoolKey
    modifier onlyPoolManager(bytes32 parameters) {
        /// @dev Make sure:
        /// 1. the pool manager specified in PoolKey is the caller
        /// 2. the pool manager has been registered
        // uint256 id = parameters.getPoolManagerId();
        address poolManager = poolManagerId[parameters.getPoolManagerId()];
        if (poolManager != msg.sender) revert NotFromPoolManager();

        if (!isPoolManagerRegistered[msg.sender]) revert PoolManagerUnregistered();

        _;
    }

    /// @notice revert if no locker is set
    modifier isLocked() {
        if (SettlementGuard.getLocker() == address(0)) revert NoLocker();
        _;
    }

    /// @inheritdoc IVault
    function registerPoolManager(address poolManager) external override onlyOwner {
        isPoolManagerRegistered[poolManager] = true;
        poolManagerId[++PoolManagerLength] = poolManager;

        emit PoolManagerRegistered(poolManager);
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
    function accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address settler)
        external
        override
        isLocked
        onlyPoolManager(key.parameters)
    {
        // uint256 id = key.parameters.getPoolManagerId();
        // IPoolManager poolManager = IPoolManager(poolManagerId[key.parameters.getPoolManagerId()]);
        IPoolManager poolManager = IPoolManager(msg.sender);

        // if (address(poolManager) != msg.sender) revert NotFromPoolManager();

        // if (!isPoolManagerRegistered[msg.sender]) revert PoolManagerUnregistered();

        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        // keep track on each pool manager
        _accountDeltaOfPoolManager(poolManager, key.currency0, delta0);
        _accountDeltaOfPoolManager(poolManager, key.currency1, delta1);

        // keep track of the balance for the whole vault
        SettlementGuard.accountDelta(settler, key.currency0, delta0);
        SettlementGuard.accountDelta(settler, key.currency1, delta1);
    }

    /// @inheritdoc IVault
    function take(Currency currency, address to, uint256 amount) external override isLocked {
        SettlementGuard.accountDelta(msg.sender, currency, -(amount.toInt128()));
        currency.transfer(to, amount);
    }

    /// @inheritdoc IVault
    function mint(address to, Currency currency, uint256 amount) external override isLocked {
        SettlementGuard.accountDelta(msg.sender, currency, -(amount.toInt128()));
        _mint(to, currency, amount);
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
    function settleFor(Currency currency, address target, uint256 amount) external isLocked {
        /// @notice settle all outstanding debt if amount is 0
        /// It will revert if target has positive delta
        if (amount == 0) amount = (-SettlementGuard.getCurrencyDelta(target, currency)).toUint256();
        SettlementGuard.accountDelta(msg.sender, currency, -(amount.toInt128()));
        SettlementGuard.accountDelta(target, currency, amount.toInt128());
    }

    /// @inheritdoc IVault
    function burn(address from, Currency currency, uint256 amount) external override isLocked {
        SettlementGuard.accountDelta(msg.sender, currency, amount.toInt128());
        _burnFrom(from, currency, amount);
    }

    /// @inheritdoc IVault
    function collectFee(Currency currency, uint256 amount, address recipient) external {
        reservesOfPoolManager[IPoolManager(msg.sender)][currency] -= amount;
        currency.transfer(recipient, amount);
    }

    /// @inheritdoc IVault
    function reservesOfVault(Currency currency) external view returns (uint256 amount) {
        return currency.getVaultReserves();
    }

    function _accountDeltaOfPoolManager(IPoolManager poolManager, Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            /// @dev arithmetic underflow make sure trader can't withdraw too much from poolManager
            reservesOfPoolManager[poolManager][currency] -= uint128(delta);
        } else {
            /// @dev arithmetic overflow make sure trader won't deposit too much into poolManager
            reservesOfPoolManager[poolManager][currency] += uint128(-delta);
        }
    }
}
