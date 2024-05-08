// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly {
            z := add(x, y)

            if shr(128, z) {
                // store 0x93dafdf1, error SafeCastOverflow at memory 0 address and revert from pointer 28, to byte 32
                mstore(0x0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
        }
    }
}
