// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract MockVault {
    using SafeCast for *;
    using CurrencyLibrary for Currency;

    mapping(address app => mapping(Currency currency => uint256 reserve)) public reservesOfApp;
    mapping(PoolId poolId => BalanceDelta delta) public balanceDeltaOfPool;

    constructor() {}

    function accountAppBalanceDelta(PoolKey memory key, BalanceDelta delta, address) external {
        PoolId poolId = key.toId();
        balanceDeltaOfPool[poolId] = delta;

        _accountDeltaForApp(address(key.poolManager), key.currency0, delta.amount0());
        _accountDeltaForApp(address(key.poolManager), key.currency1, delta.amount1());
    }

    function _accountDeltaForApp(address poolManager, Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            reservesOfApp[poolManager][currency] -= uint128(delta);
        } else {
            reservesOfApp[poolManager][currency] += uint128(-delta);
        }
    }

    function collectFee(Currency currency, uint256 amount, address recipient) external {
        _accountDeltaForApp(msg.sender, currency, -amount.toInt128());
        currency.transfer(recipient, amount);
    }
}
