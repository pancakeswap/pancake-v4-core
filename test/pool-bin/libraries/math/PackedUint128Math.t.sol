// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Constants} from "../../../../src/pool-bin/libraries/Constants.sol";
import {PackedUint128Math} from "../../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../../../src/pool-bin/libraries/math/SafeCast.sol";
import {ProtocolFeeLibrary} from "../../../../src/libraries/ProtocolFeeLibrary.sol";

contract PackedUint128MathTest is Test {
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;

    function testFuzz_Encode(uint128 x1, uint128 x2) external pure {
        assertEq(bytes32(x1 | (uint256(x2) << 128)), x1.encode(x2), "testFuzz_Encode::1");
    }

    function testFuzz_EncodeFirst(uint128 x1) external pure {
        assertEq(bytes32(uint256(x1)), x1.encodeFirst(), "testFuzz_EncodeFirst::1");
    }

    function testFuzz_EncodeSecond(uint128 x2) external pure {
        assertEq(bytes32(uint256(x2) << 128), x2.encodeSecond(), "testFuzz_EncodeSecond::1");
    }

    function testFuzz_EncodeBool(uint128 x, bool first) external pure {
        assertEq(bytes32(uint256(x) << (first ? 0 : 128)), x.encode(first), "testFuzz_EncodeBool::1");
    }

    function testFuzz_Decode(bytes32 x) external pure {
        (uint128 x1, uint128 x2) = x.decode();

        assertEq(x1, uint128(uint256(x)), "testFuzz_Decode::1");
        assertEq(x2, uint128(uint256(x) >> 128), "testFuzz_Decode::2");
    }

    function testFuzz_decodeX(bytes32 x) external pure {
        assertEq(uint128(uint256(x)), x.decodeX(), "testFuzz_decodeX::1");
    }

    function testFuzz_decodeY(bytes32 x) external pure {
        assertEq(uint128(uint256(x) >> 128), x.decodeY(), "testFuzz_decodeY::1");
    }

    function testFuzz_DecodeBool(bytes32 x, bool first) external pure {
        assertEq(uint128(uint256(x) >> (first ? 0 : 128)), x.decode(first), "testFuzz_DecodeBool::1");
    }

    function test_AddSelf() external pure {
        bytes32 x = bytes32(uint256((1 << 128) | 1));

        assertEq(x.add(x), bytes32(uint256((2 << 128) | 2)), "testFuzz_AddSelf::1");
    }

    function test_AddOverflow() external {
        bytes32 x = bytes32(type(uint256).max);

        bytes32 y1 = bytes32(uint256(1));
        bytes32 y2 = bytes32(uint256(1 << 128));
        bytes32 y3 = y1 | y2;

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        x.add(y1);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        x.add(y2);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        x.add(y3);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        y1.add(x);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        y2.add(x);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
        y3.add(x);
    }

    function testFuzz_Add(bytes32 x, bytes32 y) external {
        uint128 x1 = uint128(uint256(x));
        uint128 x2 = uint128(uint256(x >> 128));

        uint128 y1 = uint128(uint256(y));
        uint128 y2 = uint128(uint256(y >> 128));

        if (x1 <= type(uint128).max - y1 && x2 <= type(uint128).max - y2) {
            assertEq(x.add(y), bytes32(uint256(x1 + y1) | (uint256(x2 + y2) << 128)), "testFuzz_Add::1");
        } else {
            vm.expectRevert(PackedUint128Math.PackedUint128Math__AddOverflow.selector);
            x.add(y);
        }
    }

    function test_SubSelf() external pure {
        bytes32 x = bytes32(uint256((1 << 128) | 1));

        assertEq(x.sub(x), bytes32(0), "testFuzz_SubSelf::1");
    }

    function test_SubUnderflow() external {
        bytes32 x = bytes32(0);

        bytes32 y1 = bytes32(uint256(1));
        bytes32 y2 = bytes32(uint256(1 << 128));
        bytes32 y3 = y1 | y2;

        assertEq(y1.sub(x), y1, "testFuzz_SubUnderflow::1");
        assertEq(y2.sub(x), y2, "testFuzz_SubUnderflow::2");
        assertEq(y3.sub(x), y3, "testFuzz_SubUnderflow::3");

        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        x.sub(y1);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        x.sub(y2);

        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        x.sub(y3);
    }

    function testFuzz_Sub(bytes32 x, bytes32 y) external {
        uint128 x1 = uint128(uint256(x));
        uint128 x2 = uint128(uint256(x >> 128));

        uint128 y1 = uint128(uint256(y));
        uint128 y2 = uint128(uint256(y >> 128));

        if (x1 >= y1 && x2 >= y2) {
            assertEq(x.sub(y), bytes32(uint256(x1 - y1) | (uint256(x2 - y2) << 128)), "testFuzz_Sub::1");
        } else {
            vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
            x.sub(y);
        }
    }

    function testFuzz_LessThan(bytes32 x, bytes32 y) external pure {
        (uint128 x1, uint128 x2) = x.decode();
        (uint128 y1, uint128 y2) = y.decode();

        assertEq(x.lt(y), x1 < y1 || x2 < y2, "testFuzz_LessThan::1");
    }

    function testFuzz_GreaterThan(bytes32 x, bytes32 y) external pure {
        (uint128 x1, uint128 x2) = x.decode();
        (uint128 y1, uint128 y2) = y.decode();

        assertEq(x.gt(y), x1 > y1 || x2 > y2, "testFuzz_GreaterThan::1");
    }

    function testFuzz_getProtocolFeeAmt(bytes32 x, uint16 protocolFee0, uint16 protocolFee1, uint24 swapFee)
        external
        pure
    {
        protocolFee0 = uint16(bound(protocolFee0, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        protocolFee1 = uint16(bound(protocolFee1, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        uint24 protocolFee = protocolFee1 << 12 | protocolFee0;

        swapFee = uint24(bound(swapFee, protocolFee, 1_000_000));

        (uint128 x1, uint128 x2) = x.decode();

        if (protocolFee == 0 || swapFee == 0) {
            assertEq(x.getProtocolFeeAmt(protocolFee, swapFee), 0);
        } else {
            uint24 fee0 = protocolFee % 4096;
            uint24 fee1 = protocolFee >> 12;

            uint128 x1Fee = fee0 > 0 ? uint128(uint256(x1) * fee0 / swapFee) : 0;
            uint128 x2Fee = fee1 > 0 ? uint128(uint256(x2) * fee1 / swapFee) : 0;
            assertEq(x.getProtocolFeeAmt(protocolFee, swapFee), uint128(x1Fee).encode(uint128(x2Fee)));
        }
    }

    function test_getProtocolFeeAmt_Overflow() external {
        bytes32 amounts = uint128(type(uint128).max).encode(uint128(type(uint128).max));

        /// @dev This shouldn't happen as swapFee passed in will be inclusive of protocolFee
        ///      However, adding safeCast protects against future extension of v4 in the case the fee is not inclusive
        uint24 protocolFee = 100;
        uint24 swapFee = 10;

        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        amounts.getProtocolFeeAmt(protocolFee, swapFee);
    }

    function test_getProtocolFeeAmtX() external pure {
        {
            bytes32 totalFee = uint128(100).encode(uint128(100));
            uint24 protocolFee = (0 << 12) + 0; // 0% fee
            assertEq(totalFee.getProtocolFeeAmt(protocolFee, 0), 0);
        }

        {
            bytes32 totalFee = uint128(10_000).encode(uint128(10_000));
            uint24 protocolFee = (100 << 12) + 100; // 0.01% fee

            // lpFee 0%
            assertEq(totalFee.getProtocolFeeAmt(protocolFee, 100), uint128(10_000).encode(uint128(10_000)));
        }

        {
            bytes32 totalFee = uint128(10_000).encode(uint128(10_000));
            uint24 protocolFee = (1000 << 12) + 1000; // 0.1% fee

            uint24 swapFee = ProtocolFeeLibrary.calculateSwapFee(1000, 3000); // 0.1% protocolFee, 0.3% lpFee
            // protocolFee is roughly more than 1/4 as protocolFee is taken out first
            assertEq(totalFee.getProtocolFeeAmt(protocolFee, swapFee), uint128(2501).encode(uint128(2501)));
        }

        {
            bytes32 totalFee = uint128(10_000).encode(uint128(10_000));
            uint24 protocolFee = (4000 << 12) + 4000; // 0.4% fee

            uint24 swapFee = ProtocolFeeLibrary.calculateSwapFee(4000, 3000);
            // protocolFee is roughly more than 4/7 as protocolFee is taken out first
            assertEq(totalFee.getProtocolFeeAmt(protocolFee, swapFee), uint128(5724).encode(uint128(5724)));
        }
    }
}
