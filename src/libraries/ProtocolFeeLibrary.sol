// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import "./math/UnsafeMath.sol";

library ProtocolFeeLibrary {
    /// @dev Increasing these values could lead to overflow in Pool.swap
    /// @notice Max protocol fee is 0.4% (4000 pips)
    uint16 public constant MAX_PROTOCOL_FEE = 4000;

    /// @notice Thresholds used for optimized bounds checks on protocol fees
    uint24 internal constant FEE_0_THRESHOLD = 4001;
    uint24 internal constant FEE_1_THRESHOLD = 4001 << 12;

    /// @notice the protocol fee is represented in hundredths of a bip
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

    /// @notice Get the fee taken when swap token0 for token1
    /// @param self The composite protocol fee to get the single direction fee from
    /// @return The fee taken when swapping token0 for token1
    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & 0xfff);
    }

    /// @notice Get the fee taken when swap token1 for token0
    /// @param self The composite protocol fee to get the single direction fee from
    /// @return The fee taken when swapping token1 for token0
    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }

    /// @notice Validate that the protocol fee is within bounds
    /// @param self The composite protocol fee to validate
    /// @return valid True if the fee is within bounds
    function validate(uint24 self) internal pure returns (bool valid) {
        // Equivalent to: getZeroForOneFee(self) <= MAX_PROTOCOL_FEE && getOneForZeroFee(self) <= MAX_PROTOCOL_FEE
        assembly ("memory-safe") {
            let isZeroForOneFeeOk := lt(and(self, 0xfff), FEE_0_THRESHOLD)
            let isOneForZeroFeeOk := lt(and(self, 0xfff000), FEE_1_THRESHOLD)
            valid := and(isZeroForOneFeeOk, isOneForZeroFeeOk)
        }
    }

    /// @notice The protocol fee is taken from the input amount first and then the LP fee is taken from the remaining
    // Equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000 (rounded up)
    /// Also note the swap fee is capped at 1_000_000 (100%) for cl pool and 100_000 (10%) for bin pool
    /// @param self The single direction protocol fee to calculate the swap fee from
    /// @param lpFee The LP fee to calculate the swap fee from
    /// @return swapFee The composite swap fee
    function calculateSwapFee(uint16 self, uint24 lpFee) internal pure returns (uint24 swapFee) {
        // protocolFee + lpFee - (protocolFee * lpFee / 1_000_000)
        assembly ("memory-safe") {
            self := and(self, 0xfff)
            lpFee := and(lpFee, 0xffffff)
            let numerator := mul(self, lpFee)
            swapFee := sub(add(self, lpFee), div(numerator, PIPS_DENOMINATOR))
        }
    }
}
