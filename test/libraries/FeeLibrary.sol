// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {SwapFeeLibrary} from "../../src/libraries/SwapFeeLibrary.sol";

contract SwapFeeLibraryTest is Test {
    using SwapFeeLibrary for uint24;

    function testisDynamicSwapFee() public {
        // 1000 0000 0000 0000 0000 0000
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0x800000), true);

        // 0100 0000 0000 0000 0000 0000
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0x400000), false);

        // 0010 0000 0000 0000 0000 0000
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0x200000), false);

        // 0001 0000 0000 0000 0000 0000
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0x100000), false);

        // 1111 1111 1111 1111 1111 1111
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0xFFFFFF), true);

        // 0111 1111 1111 1111 1111 1111
        assertEq(SwapFeeLibrary.isDynamicSwapFee(0x7FFFF), false);
    }

    function testGetSwapFee() public {
        // static
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x000001), 0x000001);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x000002), 0x000002);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x0F0003), 0x0F0003);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x001004), 0x001004);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x111020), 0x011020);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x101020), 0x001020);

        // dynamic
        assertEq(SwapFeeLibrary.getInitialSwapFee(0xF00F05), 0);
        assertEq(SwapFeeLibrary.getInitialSwapFee(0x800310), 0);
    }

    function testFuzzIsStaicFeeTooLarge(uint24 self, uint24 maxFee) public {
        assertEq(self.getInitialSwapFee() > maxFee, self.getInitialSwapFee().isSwapFeeTooLarge(maxFee));
    }
}
