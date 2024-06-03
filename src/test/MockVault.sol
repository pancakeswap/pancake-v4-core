// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract MockVault {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    mapping(address poolManager => mapping(Currency currency => uint256 reserve)) public reservesOfPoolManager;
    mapping(Currency => int128) internal _balanceDeltaOfCurrency;

    constructor() {}

    function balanceDeltaOfPool(PoolKey memory poolKey) external view returns (BalanceDelta) {
        return toBalanceDelta(_balanceDeltaOfCurrency[poolKey.currency0], _balanceDeltaOfCurrency[poolKey.currency1]);
    }

    function accountPoolBalanceDelta(Currency currency, int128 delta, address) external {
        _balanceDeltaOfCurrency[currency] = delta;

        _accountDeltaOfPoolManager(msg.sender, currency, delta);
    }

    function _accountDeltaOfPoolManager(address poolManager, Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            reservesOfPoolManager[poolManager][currency] -= uint128(delta);
        } else {
            reservesOfPoolManager[poolManager][currency] += uint128(-delta);
        }
    }

    function collectFee(Currency currency, uint256 amount, address recipient) external {
        _accountDeltaOfPoolManager(msg.sender, currency, -amount.toInt128());
        currency.transfer(recipient, amount);
    }
}
