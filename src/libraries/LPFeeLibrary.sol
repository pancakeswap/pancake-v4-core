// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

/// @dev Library for handling lp fee setting from `PoolKey.fee`
/// It can be either static or dynamic, and upper 4 bits are used to store the flag:
/// 1. if the flag is set, then the fee is dynamic, it can be set and updated by hook
/// 2. otherwise if the flag is not set, then the fee is static, and the lower 20 bits are used to store the fee
library LPFeeLibrary {
    using LPFeeLibrary for uint24;

    /// @notice Thrown when the static/dynamic fee on a pool exceeds 100%.
    error FeeTooLarge();

    /// @dev the flag and mask
    uint24 public constant OVERRIDE_MASK = 0xBFFFFF;

    // a dynamic fee pool must have exactly same value for fee field
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    // the second bit of the fee returned by beforeSwap is used to signal if the stored LP fee should be overridden in this swap
    // only dynamic-fee pools can return a fee via the beforeSwap hook
    uint24 public constant OVERRIDE_FEE_FLAG = 0x400000;

    /// @dev the fee is represented in hundredths of a bip
    /// @dev the max fee for cl pool is 100% and for bin, it is 10%
    uint24 public constant ONE_HUNDRED_PERCENT_FEE = 1_000_000;
    uint24 public constant TEN_PERCENT_FEE = 100_000;

    function isDynamicLPFee(uint24 self) internal pure returns (bool) {
        return self == DYNAMIC_FEE_FLAG;
    }

    function validate(uint24 self, uint24 maxFee) internal pure {
        if (self > maxFee) revert FeeTooLarge();
    }

    /// @return lpFee initial lp fee for the pool. For dynamic fee pool, zero is returned
    function getInitialLPFee(uint24 self) internal pure returns (uint24 lpFee) {
        // the initial fee for a dynamic fee pool is 0
        if (self.isDynamicLPFee()) return 0;
        lpFee = self;
    }

    /// @notice returns true if the fee has the override flag set (top bit of the uint24)
    function isOverride(uint24 self) internal pure returns (bool) {
        return self & OVERRIDE_FEE_FLAG != 0;
    }

    /// @notice returns a fee with the override flag removed
    function removeOverrideFlag(uint24 self) internal pure returns (uint24) {
        return self & OVERRIDE_MASK;
    }

    /// @notice Removes the override flag and validates the fee (reverts if the fee is too large)
    function removeOverrideAndValidate(uint24 self, uint24 maxFee) internal pure returns (uint24) {
        uint24 fee = self.removeOverrideFlag();
        fee.validate(maxFee);
        return fee;
    }
}
