// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";
import {LiquidityMath} from "../../../src/pool-cl/libraries/LiquidityMath.sol";

contract LiquidityMathTest is Test, GasSnapshot {
    function testAddDelta() public {
        assertEq(LiquidityMath.addDelta(1, 0), 1);
        assertEq(LiquidityMath.addDelta(1, -1), 0);
        assertEq(LiquidityMath.addDelta(1, 1), 2);

        snapStart("LiquidityMathTest#addDeltaPositive");
        LiquidityMath.addDelta(15, 4);
        snapEnd();

        snapStart("LiquidityMathTest#addDeltaNegtive");
        LiquidityMath.addDelta(15, -4);
        snapEnd();
    }

    function testAddDeltaOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        LiquidityMath.addDelta(2 ** 128 - 15, 15);
    }

    function testAddDeltaUnderflow() public {
        // underflow
        vm.expectRevert(stdError.arithmeticError);
        LiquidityMath.addDelta(0, -1);

        vm.expectRevert(stdError.arithmeticError);
        LiquidityMath.addDelta(3, -4);
    }
}
