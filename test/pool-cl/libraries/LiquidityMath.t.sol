// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCast} from "../../../src/libraries/SafeCast.sol";
import {LiquidityMath} from "../../../src/pool-cl/libraries/LiquidityMath.sol";

contract LiquidityMathTest is Test {
    function testAddDelta() public {
        assertEq(LiquidityMath.addDelta(1, 0), 1);
        assertEq(LiquidityMath.addDelta(1, -1), 0);
        assertEq(LiquidityMath.addDelta(1, 1), 2);

        vm.startSnapshotGas("addDeltaPositive");
        LiquidityMath.addDelta(15, 4);
        vm.stopSnapshotGas();

        vm.startSnapshotGas("addDeltaNegtive");
        LiquidityMath.addDelta(15, -4);
        vm.stopSnapshotGas();
    }

    function testAddDeltaOverflow() public {
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        LiquidityMath.addDelta(2 ** 128 - 15, 15);
    }

    function testAddDeltaUnderflow() public {
        // underflow
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        LiquidityMath.addDelta(0, -1);

        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        LiquidityMath.addDelta(3, -4);
    }
}
