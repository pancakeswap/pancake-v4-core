// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {stdError} from "forge-std/StdError.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {CLPosition} from "../../../src/pool-cl/libraries/CLPosition.sol";
import {CLPool} from "../../../src/pool-cl/libraries/CLPool.sol";
import {FixedPoint128} from "../../../src/pool-cl/libraries/FixedPoint128.sol";
import {SafeCast} from "../../../src/libraries/SafeCast.sol";

contract CLPositionTest is Test, GasSnapshot {
    using CLPosition for mapping(bytes32 => CLPosition.Info);
    using CLPosition for CLPosition.Info;

    CLPool.State public pool;

    function test_get_emptyPosition() public view {
        CLPosition.Info memory info = pool.positions.get(address(this), 1, 2, 0);
        assertEq(info.liquidity, 0);
        assertEq(info.feeGrowthInside0LastX128, 0);
        assertEq(info.feeGrowthInside1LastX128, 0);
    }

    function test_set_updateEmptyPositionFuzz(
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) public {
        CLPosition.Info storage info = pool.positions.get(address(this), 1, 2, 0);

        if (liquidityDelta == 0) {
            vm.expectRevert(CLPosition.CannotUpdateEmptyPosition.selector);
        } else if (liquidityDelta < 0) {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        }
        (uint256 feesOwed0, uint256 feesOwed1) = info.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        assertEq(feesOwed0, 0);
        assertEq(feesOwed1, 0);
        assertEq(info.liquidity, uint128(liquidityDelta));
        assertEq(info.feeGrowthInside0LastX128, feeGrowthInside0X128);
        assertEq(info.feeGrowthInside1LastX128, feeGrowthInside1X128);
    }

    function test_set_updateNonEmptyPosition() public {
        CLPosition.Info storage info = pool.positions.get(address(this), 1, 2, 0);

        // init
        {
            (uint256 feesOwed0, uint256 feesOwed1) = info.update(3, 5 * FixedPoint128.Q128, 6 * FixedPoint128.Q128);
            assertEq(feesOwed0, 0);
            assertEq(feesOwed1, 0);
        }

        // add
        {
            snapStart("CLPositionTest#Position_update_add");
            (uint256 feesOwed0, uint256 feesOwed1) = info.update(0, 10 * FixedPoint128.Q128, 12 * FixedPoint128.Q128);
            snapEnd();
            assertEq(feesOwed0, (10 - 5) * 3);
            assertEq(feesOwed1, (12 - 6) * 3);

            assertEq(info.liquidity, 3);
            assertEq(info.feeGrowthInside0LastX128, 10 * FixedPoint128.Q128);
            assertEq(info.feeGrowthInside1LastX128, 12 * FixedPoint128.Q128);
        }

        // remove
        {
            (uint256 feesOwed0, uint256 feesOwed1) = info.update(-1, 10 * FixedPoint128.Q128, 12 * FixedPoint128.Q128);
            assertEq(feesOwed0, 0);
            assertEq(feesOwed1, 0);

            assertEq(info.liquidity, 2);
            assertEq(info.feeGrowthInside0LastX128, 10 * FixedPoint128.Q128);
            assertEq(info.feeGrowthInside1LastX128, 12 * FixedPoint128.Q128);
        }

        // remove all
        {
            snapStart("CLPositionTest#Position_update_remove");
            (uint256 feesOwed0, uint256 feesOwed1) = info.update(-2, 20 * FixedPoint128.Q128, 15 * FixedPoint128.Q128);
            snapEnd();
            assertEq(feesOwed0, (20 - 10) * 2);
            assertEq(feesOwed1, (15 - 12) * 2);

            assertEq(info.liquidity, 0);
            assertEq(info.feeGrowthInside0LastX128, 20 * FixedPoint128.Q128);
            assertEq(info.feeGrowthInside1LastX128, 15 * FixedPoint128.Q128);
        }
    }

    function test_MixFuzz(address owner, int24 tickLower, int24 tickUpper, bytes32 salt, int128 liquidityDelta)
        public
    {
        liquidityDelta = int128(bound(liquidityDelta, 1, type(int128).max));
        CLPosition.Info storage info = pool.positions.get(owner, tickLower, tickUpper, salt);
        info.update(liquidityDelta, 0, 0);

        bytes32 key = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt));
        assertEq(pool.positions[key].liquidity, uint128(liquidityDelta));
    }
}
