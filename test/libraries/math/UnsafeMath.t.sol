// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UnsafeMath} from "../../../src/libraries/math/UnsafeMath.sol";

contract UnsafeMathTest is Test {
    function testDivRoundingUpFuzz(uint256 x, uint256 d) external pure {
        vm.assume(d != 0);
        uint256 z = UnsafeMath.divRoundingUp(x, d);
        uint256 diff = z - (x / d);
        if (x % d == 0) {
            assertEq(diff, 0);
        } else {
            assertEq(diff, 1);
        }
    }
}
