// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import "./math/UnsafeMath.sol";

library ProtocolFeeLibrary {
    // Max protocol fee is 0.1% (1000 pips)
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    // Thresholds used for optimized bounds checks on protocol fees
    uint24 internal constant FEE_0_THRESHOLD = 1001;
    uint24 internal constant FEE_1_THRESHOLD = 1001 << 12;

    // the protocol fee is represented in hundredths of a bip
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & 0xfff);
    }

    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }

    function validate(uint24 self) internal pure returns (bool valid) {
        // Equivalent to: getZeroForOneFee(self) <= MAX_PROTOCOL_FEE && getOneForZeroFee(self) <= MAX_PROTOCOL_FEE
        assembly ("memory-safe") {
            let isZeroForOneFeeOk := lt(and(self, 0xfff), FEE_0_THRESHOLD)
            let isOneForZeroFeeOk := lt(self, FEE_1_THRESHOLD)
            valid := and(isZeroForOneFeeOk, isOneForZeroFeeOk)
        }
    }

    // The protocol fee is taken from the input amount first and then the LP fee is taken from the remaining
    // The swap fee is capped at 1_000_000 (100%) for cl pool and 100_000 (10%) for bin pool
    // Equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000
    function calculateSwapFee(uint24 self, uint24 lpFee) internal pure returns (uint24 swapFee) {
        assembly ("memory-safe") {
            let numerator := mul(self, lpFee)
            let divRoundingUp := add(div(numerator, PIPS_DENOMINATOR), gt(mod(numerator, PIPS_DENOMINATOR), 0))
            swapFee := sub(add(self, lpFee), divRoundingUp)
        }
    }
}
