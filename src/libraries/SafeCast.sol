// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    error SafeCastOverflow();

    function _revertOverflow() private pure {
        assembly ("memory-safe") {
            // Store the function selector of `SafeCastOverflow()`.
            mstore(0x00, 0x93dafdf1)
            // Revert with (offset, size).
            revert(0x1c, 0x04)
        }
    }

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type uint160
    function toUint160(uint256 x) internal pure returns (uint160 y) {
        y = uint160(x);
        if (y != x) _revertOverflow();
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param x The int256 to be downcasted
    /// @return y The downcasted integer, now type int128
    function toInt128(int256 x) internal pure returns (int128 y) {
        y = int128(x);
        if (y != x) _revertOverflow();
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param x The uint256 to be casted
    /// @return y The casted integer, now type int256
    function toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        if (y < 0) _revertOverflow();
    }

    /// @notice Cast a int256 to a uint256, revert on overflow
    /// @param x The int256 to be casted
    /// @return y The casted integer, now type uint256
    function toUint256(int256 x) internal pure returns (uint256 y) {
        if (x < 0) _revertOverflow();
        y = uint256(x);
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @param x The uint256 to be downcasted
    /// @return The downcasted integer, now type int128
    function toInt128(uint256 x) internal pure returns (int128) {
        if (x >= 1 << 127) _revertOverflow();
        return int128(int256(x));
    }
}
