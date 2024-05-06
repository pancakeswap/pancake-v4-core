// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";

contract LPFeeLibraryTest is Test {
    using LPFeeLibrary for uint24;

    function testIsDynamicLPFee() public {
        // 1000 0000 0000 0000 0000 0000
        assertEq(LPFeeLibrary.isDynamicLPFee(0x800000), true);

        // 0100 0000 0000 0000 0000 0000
        assertEq(LPFeeLibrary.isDynamicLPFee(0x400000), false);

        // 0010 0000 0000 0000 0000 0000
        assertEq(LPFeeLibrary.isDynamicLPFee(0x200000), false);

        // 0001 0000 0000 0000 0000 0000
        assertEq(LPFeeLibrary.isDynamicLPFee(0x100000), false);

        // 1111 1111 1111 1111 1111 1111
        assertEq(LPFeeLibrary.isDynamicLPFee(0xFFFFFF), true);

        // 0111 1111 1111 1111 1111 1111
        assertEq(LPFeeLibrary.isDynamicLPFee(0x7FFFF), false);
    }

    function testGetInitialLPFee() public {
        // static
        assertEq(LPFeeLibrary.getInitialLPFee(0x000001), 0x000001);
        assertEq(LPFeeLibrary.getInitialLPFee(0x000002), 0x000002);
        assertEq(LPFeeLibrary.getInitialLPFee(0x0F0003), 0x0F0003);
        assertEq(LPFeeLibrary.getInitialLPFee(0x001004), 0x001004);
        assertEq(LPFeeLibrary.getInitialLPFee(0x111020), 0x011020);
        assertEq(LPFeeLibrary.getInitialLPFee(0x101020), 0x001020);

        // dynamic
        assertEq(LPFeeLibrary.getInitialLPFee(0xF00F05), 0);
        assertEq(LPFeeLibrary.getInitialLPFee(0x800310), 0);
    }

    function testFuzzValidate(uint24 self, uint24 maxFee) public {
        if (self > maxFee) {
            vm.expectRevert(LPFeeLibrary.FeeTooLarge.selector);
        }
        LPFeeLibrary.validate(self, maxFee);
    }
}
