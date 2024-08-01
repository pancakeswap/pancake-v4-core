// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {Constants} from "./Constants.sol";

/// @notice Helper to calculate fees for BinPool
library FeeHelper {
    /// @dev Calculates the fee amount from the amount with fees, rounding up
    /// @param amountWithFees The amount with fees
    /// @param feeBips feeBips - 100 = 0.01%, 1_000 = 0.1%, 100_000 = 10% (max)
    /// @return feeAmount The fee amount
    function getFeeAmountFrom(uint128 amountWithFees, uint24 feeBips) internal pure returns (uint128) {
        unchecked {
            uint128 totalFee = uint128(feeBips) * 1e12;
            // Can't overflow, max(result) = (type(uint128).max * 0.1e18 + 1e18 - 1) / 1e18 < 2^128
            return uint128((uint256(amountWithFees) * totalFee + Constants.PRECISION - 1) / Constants.PRECISION);
        }
    }

    /// @dev Calculates the fee amount that will be charged, rounding up
    /// @param amount The amount
    /// @param feeBips feeBips - 100 = 0.01%, 1_000 = 0.1%, 100_000 = 10% (max)
    /// @return feeAmount The fee amount
    function getFeeAmount(uint128 amount, uint24 feeBips) internal pure returns (uint128) {
        unchecked {
            uint128 totalFee = uint128(feeBips) * 1e12;
            uint256 denominator = Constants.PRECISION - totalFee;
            // Can't overflow, max(result) = (type(uint128).max * 0.1e18 + (1e18 - 1)) / 0.9e18 < 2^128
            return uint128((uint256(amount) * totalFee + denominator - 1) / denominator);
        }
    }

    /// @notice Calculates the composition fee amount from the amount with fees, rounding down
    /// @dev Composition fee is higher than swapFee to ensure user do not does an implicit swap through mint to take advantage of lower fees
    /// @param amountWithFees The amount with fees
    /// @param feeBips The total fee, 100 = 0.01%, 10_000 = 1%, 100_000 = 10% (max)
    /// @return The amount with fees
    function getCompositionFee(uint128 amountWithFees, uint24 feeBips) internal pure returns (uint128) {
        unchecked {
            uint128 totalFee = uint128(feeBips) * 1e12;
            uint256 denominator = Constants.SQUARED_PRECISION; // 1e36
            // Can't overflow, max(result) = type(uint128).max * 0.1e18 * 1.1e18 / 1e36 <= 2^128 * 0.11e36 / 1e36 < 2^128
            return
                uint128((uint256(amountWithFees) * totalFee * (uint256(totalFee) + Constants.PRECISION)) / denominator);
        }
    }
}
