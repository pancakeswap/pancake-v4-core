// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/// @notice Library for handling lp fee setting from `PoolKey.fee`
/// It can be either static or dynamic, and upper 4 bits are used to store the flag:
/// 1. if the flag is set, then the fee is dynamic, it can be set and updated by hook
/// 2. otherwise if the flag is not set, then the fee is static, and the lower 20 bits are used to store the fee
library LPFeeLibrary {
    using LPFeeLibrary for uint24;

    /// @notice Thrown when the static/dynamic fee on a pool exceeds 100%.
    error LPFeeTooLarge(uint24 fee);

    /// @notice mask to remove the override fee flag from a fee returned by the beforeSwaphook
    uint24 public constant OVERRIDE_MASK = 0xBFFFFF;

    /// @notice a dynamic fee pool must have exactly same value for fee field
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    /// @notice the second bit of the fee returned by beforeSwap is used to signal if the stored LP fee should be overridden in this swap
    // only dynamic-fee pools can return a fee via the beforeSwap hook
    uint24 public constant OVERRIDE_FEE_FLAG = 0x400000;

    /// @notice the fee is represented in hundredths of a bip
    /// max fee varies between different pool types i.e. it's 100% for cl pool and 10% for bin pool
    uint24 public constant ONE_HUNDRED_PERCENT_FEE = 1_000_000;
    uint24 public constant TEN_PERCENT_FEE = 100_000;

    /// @notice returns true if a pool's LP fee signals that the pool has a dynamic fee
    /// @param self The fee to check
    /// @return bool True of the fee is dynamic
    function isDynamicLPFee(uint24 self) internal pure returns (bool) {
        return self == DYNAMIC_FEE_FLAG;
    }

    /// @notice validates whether an LP fee is larger than the maximum, and reverts if invalid
    /// @param self The fee to validate
    /// @param maxFee The maximum fee allowed for the pool
    function validate(uint24 self, uint24 maxFee) internal pure {
        if (self > maxFee) revert LPFeeTooLarge(self);
    }

    /// @notice gets the initial LP fee for a pool. Dynamic fee pools have an initial fee of 0.
    /// @dev if a dynamic fee pool wants a non-0 initial fee, it should call `updateDynamicLPFee` in the afterInitialize hook
    /// @param self The fee to get the initial LP from
    /// @return initialFee 0 if the fee is dynamic, otherwise the original value
    function getInitialLPFee(uint24 self) internal pure returns (uint24 initialFee) {
        // the initial fee for a dynamic fee pool is 0
        if (self.isDynamicLPFee()) return 0;
        initialFee = self;
    }

    /// @notice returns true if the fee has the override flag set (2nd highest bit of the uint24)
    /// @param self The fee to check
    /// @return bool True of the fee has the override flag set
    function isOverride(uint24 self) internal pure returns (bool) {
        return self & OVERRIDE_FEE_FLAG != 0;
    }

    /// @notice returns a fee with the override flag removed
    /// @param self The fee to remove the override flag from
    /// @return fee The fee without the override flag set
    function removeOverrideFlag(uint24 self) internal pure returns (uint24) {
        return self & OVERRIDE_MASK;
    }

    /// @notice Removes the override flag and validates the fee (reverts if the fee is too large)
    /// @param self The fee to remove the override flag from, and then validate
    /// @param maxFee The maximum fee allowed for the pool
    /// @return fee The fee without the override flag set (if valid)
    function removeOverrideAndValidate(uint24 self, uint24 maxFee) internal pure returns (uint24) {
        uint24 fee = self.removeOverrideFlag();
        fee.validate(maxFee);
        return fee;
    }
}
