// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../interfaces/IVault.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract MockVault {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    mapping(IPoolManager poolManager => mapping(Currency currency => uint256 reserve)) public reservesOfPoolManager;
    mapping(PoolId poolId => BalanceDelta delta) public balanceDeltaOfPool;

    constructor() {}

    function accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address) external {
        PoolId poolId = key.toId();
        balanceDeltaOfPool[poolId] = delta;

        _accountDeltaOfPoolManager(key.poolManager, key.currency0, delta.amount0());
        _accountDeltaOfPoolManager(key.poolManager, key.currency1, delta.amount1());
    }

    function _accountDeltaOfPoolManager(IPoolManager poolManager, Currency currency, int128 delta) internal {
        if (delta == 0) return;

        if (delta >= 0) {
            reservesOfPoolManager[poolManager][currency] -= uint128(delta);
        } else {
            reservesOfPoolManager[poolManager][currency] += uint128(-delta);
        }
    }

    function collectFee(Currency currency, uint256 amount, address recipient) external {
        _accountDeltaOfPoolManager(IPoolManager(msg.sender), currency, -amount.toInt128());
        currency.transfer(recipient, amount);
    }
}
