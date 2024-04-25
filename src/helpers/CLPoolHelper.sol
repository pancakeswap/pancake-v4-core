// SPDX-License-Identifier: UNLICENSED
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {PoolId, PoolIdLibrary, PoolKey} from "../types/PoolId.sol";
import {ICLPoolManagerView} from "./interfaces/ICLPoolManagerView.sol";
import {CLPool} from "../pool-cl/libraries/CLPool.sol";

contract CLPoolHelper {
    using PoolIdLibrary for PoolKey;

    struct PoolInfo {
        PoolId poolId;
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // protocol swap fee represented as integer denominator (1/x), taken as a % of the LP swap fee
        // upper 8 bits are for 1->0, and the lower 8 are for 0->1
        // the minimum permitted denominator is 4 - meaning the maximum protocol fee is 25%
        // granularity is increments of 0.38% (100/type(uint8).max)
        /// bits          16 14 12 10 8  6  4  2  0
        ///               |         swap          |
        ///               ┌───────────┬───────────┬
        /// protocolFee : |  1->0     |  0 -> 1   |
        ///               └───────────┴───────────┴
        uint16 protocolFee;
        // used for the swap fee, either static at initialize or dynamic via hook
        uint24 swapFee;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        /// @dev current active liquidity
        uint128 liquidity;
    }

    ICLPoolManagerView public immutable poolManager;

    constructor(address _poolManager) {
        poolManager = ICLPoolManagerView(_poolManager);
    }

    function getPoolId(PoolKey memory key) public pure returns (PoolId) {
        return key.toId();
    }

    function getPoolInfoByIndex(uint256 poolIndex) public view returns (PoolInfo memory) {
        PoolId poolId = poolManager.poolIds(poolIndex);
        ICLPoolManagerView.CLPoolState memory poolState = poolManager.pools(poolId);
        return PoolInfo({
            poolId: poolId,
            sqrtPriceX96: poolState.slot0.sqrtPriceX96,
            tick: poolState.slot0.tick,
            protocolFee: poolState.slot0.protocolFee,
            swapFee: poolState.slot0.swapFee,
            feeGrowthGlobal0X128: poolState.feeGrowthGlobal0X128,
            feeGrowthGlobal1X128: poolState.feeGrowthGlobal1X128,
            liquidity: poolState.liquidity
        });
    }
}
