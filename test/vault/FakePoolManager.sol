// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

contract FakePoolManager is IPoolManager {
    IVault public vault;

    mapping(PoolId id => PoolKey) public poolIdToPoolKey;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function mockAccounting(PoolKey calldata poolKey, int128 delta0, int128 delta1) external {
        vault.accountAppBalanceDelta(poolKey.currency0, poolKey.currency1, toBalanceDelta(delta0, delta1), msg.sender);
    }

    function mockAccountingWithHookDelta(
        PoolKey calldata poolKey,
        int128 delta0,
        int128 delta1,
        int128 hookDelta0,
        int128 hookDelta1
    ) external {
        vault.accountAppBalanceDelta(
            poolKey.currency0,
            poolKey.currency1,
            toBalanceDelta(delta0, delta1),
            msg.sender,
            toBalanceDelta(hookDelta0, hookDelta1),
            address(poolKey.hooks)
        );
    }

    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicSwapFee) external override {}
}
