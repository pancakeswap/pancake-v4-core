// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CLPoolGetters} from "../../../src/pool-cl/libraries/CLPoolGetters.sol";
import {CLPool} from "../../../src/pool-cl/libraries/CLPool.sol";
import {Tick} from "../../../src/pool-cl/libraries/Tick.sol";

contract CLPoolGettersTest is Test {
    CLPool.State pool;

    using CLPoolGetters for CLPool.State;

    function testGetPoolTickInfo() public {
        // info stored for each initialized individual tick
        // struct Info {
        //     uint128 liquidityGross;
        //     int128 liquidityNet;
        //     uint256 feeGrowthOutside0X128;
        //     uint256 feeGrowthOutside1X128;
        // }

        int24 tick = 5;
        int24 randomTick = 15;

        {
            Tick.Info memory info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            pool.ticks[tick] = Tick.Info(100, 200, 300, 400);
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 100);
            assertEq(info.liquidityNet, 200);
            assertEq(info.feeGrowthOutside0X128, 300);
            assertEq(info.feeGrowthOutside1X128, 400);

            // access random tick
            info = pool.getPoolTickInfo(randomTick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            // tick clear
            delete pool.ticks[tick];
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);
        }

        tick = -5;
        randomTick = -15;
        {
            Tick.Info memory info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            pool.ticks[tick] = Tick.Info(100, 200, 300, 400);
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 100);
            assertEq(info.liquidityNet, 200);
            assertEq(info.feeGrowthOutside0X128, 300);
            assertEq(info.feeGrowthOutside1X128, 400);

            // access random tick
            info = pool.getPoolTickInfo(randomTick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            // tick clear
            delete pool.ticks[tick];
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);
        }

        tick = 0;
        randomTick = type(int24).max;
        {
            Tick.Info memory info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            pool.ticks[tick] = Tick.Info(100, 200, 300, 400);
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 100);
            assertEq(info.liquidityNet, 200);
            assertEq(info.feeGrowthOutside0X128, 300);
            assertEq(info.feeGrowthOutside1X128, 400);

            // access random tick
            info = pool.getPoolTickInfo(randomTick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);

            // tick clear
            delete pool.ticks[tick];
            info = pool.getPoolTickInfo(tick);
            assertEq(info.liquidityGross, 0);
            assertEq(info.liquidityNet, 0);
            assertEq(info.feeGrowthOutside0X128, 0);
            assertEq(info.feeGrowthOutside1X128, 0);
        }
    }

    function testGetPoolBitmapInfo() public {
        uint256 bitmap = pool.getPoolBitmapInfo(10);
        assertEq(bitmap, 0);

        pool.tickBitmap[10] = 100;
        bitmap = pool.getPoolBitmapInfo(10);
        assertEq(bitmap, 100);

        // access random word
        bitmap = pool.getPoolBitmapInfo(100);
        assertEq(bitmap, 0);

        // set it back
        pool.tickBitmap[10] = 0;
        pool.getPoolBitmapInfo(10);
        assertEq(bitmap, 0);
    }

    function testGetFeeGrowthGlobals() public {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = pool.getFeeGrowthGlobals();
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        pool.feeGrowthGlobal0X128 = 100;
        pool.feeGrowthGlobal1X128 = 200;
        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = pool.getFeeGrowthGlobals();
        assertEq(feeGrowthGlobal0X128, 100);
        assertEq(feeGrowthGlobal1X128, 200);

        // set it back
        pool.feeGrowthGlobal0X128 = 0;
        pool.feeGrowthGlobal1X128 = 0;
        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = pool.getFeeGrowthGlobals();
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);
    }
}
