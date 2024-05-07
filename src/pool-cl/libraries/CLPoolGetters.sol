// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {CLPool} from "./CLPool.sol";
import {Tick} from "./Tick.sol";

library CLPoolGetters {
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
