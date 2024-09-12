// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency, CurrencyLibrary, equals as currencyEquals} from "../types/Currency.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract MockVault {
    using SafeCast for *;
    using CurrencyLibrary for Currency;

    mapping(address app => mapping(Currency currency => uint256 reserve)) public reservesOfApp;

    // Need to update this when try to record balanceDeltaOfPool
    PoolKey public currentPoolKey;
    mapping(PoolId poolId => BalanceDelta delta) public balanceDeltaOfPool;

    error InvalidPoolKey();

    constructor() {}

    function updateCurrentPoolKey(PoolKey memory key) external {
        currentPoolKey = key;
    }

    function accountAppBalanceDelta(Currency currency0, Currency currency1, BalanceDelta delta, address) external {
        // Will not record balanceDeltaOfPool if currentPoolKey is not set
        if (!currentPoolKey.currency0.isNative() || !currentPoolKey.currency1.isNative()) {
            // Check if currency0/currency1 is the same as the currency in currentPoolKey
            if (currentPoolKey.currency0 == currency0 && currentPoolKey.currency1 == currency1) {
                PoolId poolId = currentPoolKey.toId();
                balanceDeltaOfPool[poolId] = delta;
            } else {
                revert InvalidPoolKey();
            }
        }
        _accountDeltaForApp(currency0, delta.amount0());
        _accountDeltaForApp(currency1, delta.amount1());
    }

    function _accountDeltaForApp(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            /// @dev arithmetic underflow make sure trader can't withdraw too much from app
            reservesOfApp[msg.sender][currency] -= uint128(delta);
        } else {
            /// @dev arithmetic overflow make sure trader won't deposit too much into app
            reservesOfApp[msg.sender][currency] += uint128(-delta);
        }
    }

    function collectFee(Currency currency, uint256 amount, address recipient) external {
        _accountDeltaForApp(currency, -amount.toInt128());
        currency.transfer(recipient, amount);
    }
}
