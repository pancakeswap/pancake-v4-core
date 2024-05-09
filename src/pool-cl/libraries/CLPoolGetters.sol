// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {CLPool} from "./CLPool.sol";
import {CLPosition} from "./CLPosition.sol";
import {Tick} from "./Tick.sol";

library CLPoolGetters {
    struct PositionInfo {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    function getPoolNumPositions(CLPool.State storage pool) internal view returns (uint256) {
        return pool.positionKeys.length;
    }

    function getPoolPositionInfo(CLPool.State storage pool, uint256 index)
        internal
        view
        returns (PositionInfo memory)
    {
        CLPool.PositionKey memory key = pool.positionKeys[index];
        CLPosition.Info memory info = pool.positions[CLPosition.hashKey(key.owner, key.tickLower, key.tickUpper)];
        return PositionInfo({
            owner: key.owner,
            tickLower: key.tickLower,
            tickUpper: key.tickUpper,
            liquidity: info.liquidity,
            feeGrowthInside0LastX128: info.feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: info.feeGrowthInside1LastX128
        });
    }

    function getPoolTickInfo(CLPool.State storage pool, int24 tick) internal view returns (Tick.Info memory) {
        return pool.ticks[tick];
    }

    function getPoolBitmapInfo(CLPool.State storage pool, int16 word) internal view returns (uint256 tickBitmap) {
        return pool.tickBitmap[word];
    }

    function getFeeGrowthGlobals(CLPool.State storage pool)
        internal
        view
        returns (uint256 feeGrowthGlobal0x128, uint256 feeGrowthGlobal1x128)
    {
        return (pool.feeGrowthGlobal0X128, pool.feeGrowthGlobal1X128);
    }
}
