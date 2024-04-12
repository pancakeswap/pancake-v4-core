// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

/// @dev Library for parsing swap fee info from PoolKey.fee:
/// 24 bits (upper 4 bits are used to store flag, if swap fee is static, parse lower 20 bits to get swap fee)
/// 1. flag to indicate the activation of dynamic swap fee, otherwise static swap fee is used
///     - if dynamic swap fee is activated, then the swap fee can be updated by hook
///     - if dynamic swap fee is not activated, then the swap fee is controlled by PoolKey.fee itself
/// 2. protocol fee is controlled by protocolFeeController, not PoolKey.fee
///     - protocol fee is controlled by IProtocolFeeController(hook).protocolFeeForPool()
library SwapFeeLibrary {
    using SwapFeeLibrary for uint24;

    /// @dev swap fee is stored in PoolKey as uint24
    uint24 public constant STATIC_FEE_MASK = 0x0FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000; // 1000

    /// @dev used as max swap fee for a pool. for CL, its 100%, for bin, its 10%
    uint24 public constant ONE_HUNDRED_PERCENT_FEE = 1_000_000;
    uint24 public constant TEN_PERCENT_FEE = 100_000;

    // swap fee for LP
    function isDynamicSwapFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function isSwapFeeTooLarge(uint24 self, uint24 maxFee) internal pure returns (bool) {
        return self > maxFee;
    }

    function getSwapFee(uint24 self) internal pure returns (uint24 swapFee) {
        // the initial fee for a dynamic fee pool is 0
        if (self.isDynamicSwapFee()) return 0;
        swapFee = self & STATIC_FEE_MASK;
    }
}
