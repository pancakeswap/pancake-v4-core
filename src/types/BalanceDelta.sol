//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type BalanceDelta is int256;

using {add as +, sub as -, eq as ==} for BalanceDelta global;
using BalanceDeltaLibrary for BalanceDelta global;

function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta balanceDelta) {
    /// @solidity memory-safe-assembly
    assembly {
        balanceDelta :=
            or(shl(128, _amount0), and(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff, _amount1))
    }
}

function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    return toBalanceDelta(a.amount0() + b.amount0(), a.amount1() + b.amount1());
}

function sub(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    return toBalanceDelta(a.amount0() - b.amount0(), a.amount1() - b.amount1());
}

function eq(BalanceDelta a, BalanceDelta b) pure returns (bool) {
    return a.amount0() == b.amount0() && a.amount1() == b.amount1();
}

library BalanceDeltaLibrary {
    // Sentinel return value used to signify that a NoOp occurred.
    BalanceDelta public constant MAXIMUM_DELTA = BalanceDelta.wrap(int256(type(uint256).max));

    // Sentinel return value used for feeDelta to signify that a NoOp occurred.
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);

    function amount0(BalanceDelta balanceDelta) internal pure returns (int128 _amount0) {
        /// @solidity memory-safe-assembly
        assembly {
            _amount0 := shr(128, balanceDelta)
        }
    }

    function amount1(BalanceDelta balanceDelta) internal pure returns (int128 _amount1) {
        /// @solidity memory-safe-assembly
        assembly {
            _amount1 := balanceDelta
        }
    }
}
