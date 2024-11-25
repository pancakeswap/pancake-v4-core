// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/// @notice Set of constants for BinPool
library Constants {
    uint8 internal constant SCALE_OFFSET = 128;
    uint256 internal constant SCALE = 1 << SCALE_OFFSET;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant SQUARED_PRECISION = PRECISION * PRECISION;

    uint256 internal constant BASIS_POINT_MAX = 10_000;

    // (2^256 - 1) / (2 * log(2**128) / log(1.0001))
    uint256 internal constant MAX_LIQUIDITY_PER_BIN =
        65251743116719673010965625540244653191619923014385985379600384103134737;
}
