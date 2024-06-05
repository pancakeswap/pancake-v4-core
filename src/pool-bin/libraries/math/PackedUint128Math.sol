// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Constants} from "../Constants.sol";
import {ProtocolFeeLibrary} from "../../../libraries/ProtocolFeeLibrary.sol";

/// @notice This library contains functions to encode and decode two uint128 into a single bytes32
///         and interact with the encoded bytes32.
library PackedUint128Math {
    using ProtocolFeeLibrary for uint24;

    error PackedUint128Math__AddOverflow();
    error PackedUint128Math__SubUnderflow();

    uint256 private constant OFFSET = 128;
    uint256 private constant MASK_128 = 0xffffffffffffffffffffffffffffffff;
    uint256 private constant MASK_128_PLUS_ONE = MASK_128 + 1;

    /// @dev Encodes two uint128 into a single bytes32
    /// @param x1 The first uint128
    /// @param x2 The second uint128
    /// @return z The encoded bytes32 as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    function encode(uint128 x1, uint128 x2) internal pure returns (bytes32 z) {
        assembly ("memory-safe") {
            z := or(and(x1, MASK_128), shl(OFFSET, x2))
        }
    }

    /// @dev Encodes a uint128 into a single bytes32 as the first uint128
    /// @param x1 The uint128
    /// @return z The encoded bytes32 as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: empty
    function encodeFirst(uint128 x1) internal pure returns (bytes32 z) {
        assembly ("memory-safe") {
            z := and(x1, MASK_128)
        }
    }

    /// @dev Encodes a uint128 into a single bytes32 as the second uint128
    /// @param x2 The uint128
    // @return z The encoded bytes32 as follows:
    /// [0 - 128[: empty
    /// [128 - 256[: x2
    function encodeSecond(uint128 x2) internal pure returns (bytes32 z) {
        assembly ("memory-safe") {
            z := shl(OFFSET, x2)
        }
    }

    /// @dev Encodes a uint128 into a single bytes32 as the first or second uint128
    /// @param x The uint128
    /// @param first Whether to encode as the first or second uint128
    /// @return z The encoded bytes32 as follows:
    /// if first:
    /// [0 - 128[: x
    /// [128 - 256[: empty
    /// else:
    /// [0 - 128[: empty
    /// [128 - 256[: x
    function encode(uint128 x, bool first) internal pure returns (bytes32 z) {
        return first ? encodeFirst(x) : encodeSecond(x);
    }

    /// @dev Decodes a bytes32 into two uint128
    /// @param z The encoded bytes32 as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @return x1 The first uint128
    /// @return x2 The second uint128
    function decode(bytes32 z) internal pure returns (uint128 x1, uint128 x2) {
        assembly ("memory-safe") {
            x1 := and(z, MASK_128)
            x2 := shr(OFFSET, z)
        }
    }

    /// @dev Decodes a bytes32 into a uint128 as the first uint128
    /// @param z The encoded bytes32 as follows:
    /// [0 - 128[: x
    /// [128 - 256[: any
    /// @return x The first uint128
    function decodeX(bytes32 z) internal pure returns (uint128 x) {
        assembly ("memory-safe") {
            x := and(z, MASK_128)
        }
    }

    /// @dev Decodes a bytes32 into a uint128 as the second uint128
    /// @param z The encoded bytes32 as follows:
    /// [0 - 128[: any
    /// [128 - 256[: y
    /// @return y The second uint128
    function decodeY(bytes32 z) internal pure returns (uint128 y) {
        assembly ("memory-safe") {
            y := shr(OFFSET, z)
        }
    }

    /// @dev Decodes a bytes32 into a uint128 as the first or second uint128
    /// @param z The encoded bytes32 as follows:
    /// if first:
    ///   [0 - 128[: x1
    ///   [128 - 256[: empty
    /// else:
    ///   [0 - 128[: empty
    ///  [128 - 256[: x2
    /// @param first Whether to decode as the first or second uint128
    /// @return x The decoded uint128
    function decode(bytes32 z, bool first) internal pure returns (uint128 x) {
        return first ? decodeX(z) : decodeY(z);
    }

    /// @dev Adds two encoded bytes32, reverting on overflow on any of the uint128
    /// @param x The first bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y The second bytes32 encoded as follows:
    /// [0 - 128[: y1
    /// [128 - 256[: y2
    /// @return z The sum of x and y encoded as follows:
    /// [0 - 128[: x1 + y1
    /// [128 - 256[: x2 + y2
    function add(bytes32 x, bytes32 y) internal pure returns (bytes32 z) {
        assembly ("memory-safe") {
            z := add(x, y)
        }

        if (z < x || uint128(uint256(z)) < uint128(uint256(x))) {
            revert PackedUint128Math__AddOverflow();
        }
    }

    /// @dev Adds an encoded bytes32 and two uint128, reverting on overflow on any of the uint128
    /// @param x The bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y1 The first uint128
    /// @param y2 The second uint128
    /// @return z The sum of x and y encoded as follows:
    /// [0 - 128[: x1 + y1
    /// [128 - 256[: x2 + y2
    function add(bytes32 x, uint128 y1, uint128 y2) internal pure returns (bytes32) {
        return add(x, encode(y1, y2));
    }

    /// @dev Subtracts two encoded bytes32, reverting on underflow on any of the uint128
    /// @param x The first bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y The second bytes32 encoded as follows:
    /// [0 - 128[: y1
    /// [128 - 256[: y2
    /// @return z The difference of x and y encoded as follows:
    /// [0 - 128[: x1 - y1
    /// [128 - 256[: x2 - y2
    function sub(bytes32 x, bytes32 y) internal pure returns (bytes32 z) {
        assembly ("memory-safe") {
            z := sub(x, y)
        }

        if (z > x || uint128(uint256(z)) > uint128(uint256(x))) {
            revert PackedUint128Math__SubUnderflow();
        }
    }

    /// @dev Subtracts an encoded bytes32 and two uint128, reverting on underflow on any of the uint128
    /// @param x The bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y1 The first uint128
    /// @param y2 The second uint128
    /// @return z The difference of x and y encoded as follows:
    /// [0 - 128[: x1 - y1
    /// [128 - 256[: x2 - y2
    function sub(bytes32 x, uint128 y1, uint128 y2) internal pure returns (bytes32) {
        return sub(x, encode(y1, y2));
    }

    /// @dev Returns whether any of the uint128 of x is strictly greater than the corresponding uint128 of y
    /// @param x The first bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y The second bytes32 encoded as follows:
    /// [0 - 128[: y1
    /// [128 - 256[: y2
    /// @return x1 < y1 || x2 < y2
    function lt(bytes32 x, bytes32 y) internal pure returns (bool) {
        (uint128 x1, uint128 x2) = decode(x);
        (uint128 y1, uint128 y2) = decode(y);

        return x1 < y1 || x2 < y2;
    }

    /// @dev Returns whether any of the uint128 of x is strictly greater than the corresponding uint128 of y
    /// @param x The first bytes32 encoded as follows:
    /// [0 - 128[: x1
    /// [128 - 256[: x2
    /// @param y The second bytes32 encoded as follows:
    /// [0 - 128[: y1
    /// [128 - 256[: y2
    /// @return x1 < y1 || x2 < y2
    function gt(bytes32 x, bytes32 y) internal pure returns (bool) {
        (uint128 x1, uint128 x2) = decode(x);
        (uint128 y1, uint128 y2) = decode(y);

        return x1 > y1 || x2 > y2;
    }

    /// @dev given amount and protocolFee, calculate and return external protocol fee amt
    /// @param amount encoded bytes with (x, y)
    /// @param protocolFee Protocol fee from the swap, also denominated in hundredths of a bip
    /// @param swapFee The fee collected upon every swap in the pool (including protocol fee and LP fee), denominated in hundredths of a bip
    function getExternalFeeAmt(bytes32 amount, uint24 protocolFee, uint24 swapFee) internal pure returns (bytes32 z) {
        if (protocolFee == 0 || swapFee == 0) return 0;

        (uint128 amountX, uint128 amountY) = decode(amount);
        uint16 fee0 = protocolFee.getZeroForOneFee();
        uint16 fee1 = protocolFee.getOneForZeroFee();

        uint128 feeForX;
        uint128 feeForY;
        // todo: double check on this unchecked condition
        unchecked {
            feeForX = fee0 == 0 ? 0 : uint128(uint256(amountX) * fee0 / swapFee);
            feeForY = fee1 == 0 ? 0 : uint128(uint256(amountY) * fee1 / swapFee);
        }

        return encode(feeForX, feeForY);
    }
}
