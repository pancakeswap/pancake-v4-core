// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import "./FullMath.sol";
import "./SqrtPriceMath.sol";
import "../../libraries/LPFeeLibrary.sol";

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {
    uint256 internal constant MAX_FEE_PIPS = LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE;

    /// @notice Computes the sqrt price target for the next swap step
    /// @param zeroForOne The direction of the swap, true for currency0 to currency1, false for currency1 to currency0
    /// @param sqrtPriceNextX96 The Q64.96 sqrt price for the next initialized tick
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this value
    /// after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @return sqrtPriceTargetX96 The price target for the next swap step
    function getSqrtPriceTarget(bool zeroForOne, uint160 sqrtPriceNextX96, uint160 sqrtPriceLimitX96)
        internal
        pure
        returns (uint160 sqrtPriceTargetX96)
    {
        assembly ("memory-safe") {
            // a flag to toggle between sqrtPriceNextX96 and sqrtPriceLimitX96
            // when zeroForOne == true, nextOrLimit reduces to sqrtPriceNextX96 >= sqrtPriceLimitX96
            // sqrtPriceTargetX96 = max(sqrtPriceNextX96, sqrtPriceLimitX96)
            // when zeroForOne == false, nextOrLimit reduces to sqrtPriceNextX96 < sqrtPriceLimitX96
            // sqrtPriceTargetX96 = min(sqrtPriceNextX96, sqrtPriceLimitX96)
            sqrtPriceNextX96 := and(sqrtPriceNextX96, 0xffffffffffffffffffffffffffffffffffffffff)
            sqrtPriceLimitX96 := and(sqrtPriceLimitX96, 0xffffffffffffffffffffffffffffffffffffffff)
            let nextOrLimit := xor(lt(sqrtPriceNextX96, sqrtPriceLimitX96), and(zeroForOne, 0x1))
            let symDiff := xor(sqrtPriceNextX96, sqrtPriceLimitX96)
            sqrtPriceTargetX96 := xor(sqrtPriceLimitX96, mul(symDiff, nextOrLimit))
        }
    }

    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
    /// @param sqrtRatioTargetX96 The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
    /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
    /// @return sqrtRatioNextX96 The price after swapping the amount in/out, not to exceed the price target
    /// @return amountIn The amount to be swapped in, of either token0 or token1, based on the direction of the swap
    /// @return amountOut The amount to be received, of either token0 or token1, based on the direction of the swap
    /// @return feeAmount The amount of input that will be taken as a fee
    /// @dev feePips must be no larger than MAX_FEE_PIPS for this function. We ensure that before setting a fee using LPFeeLibrary.validate.
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal pure returns (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        unchecked {
            uint256 _feePips = feePips; // upcast once and cache
            bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
            bool exactIn = amountRemaining < 0;

            if (exactIn) {
                uint256 amountRemainingLessFee =
                    FullMath.mulDiv(uint256(-amountRemaining), MAX_FEE_PIPS - _feePips, MAX_FEE_PIPS);
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);
                if (amountRemainingLessFee >= amountIn) {
                    // `amountIn` is capped by the target price
                    sqrtRatioNextX96 = sqrtRatioTargetX96;
                    feeAmount = _feePips == MAX_FEE_PIPS
                        ? amountIn
                        : FullMath.mulDivRoundingUp(amountIn, _feePips, MAX_FEE_PIPS - _feePips);
                } else {
                    sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                        sqrtRatioCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                    );
                    amountIn = zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true)
                        : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
                    // we didn't reach the target, so take the remainder of the maximum input as fee
                    feeAmount = uint256(-amountRemaining) - amountIn;
                }
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
            } else {
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);
                if (uint256(amountRemaining) >= amountOut) {
                    // `amountOut` is capped by the target price
                    sqrtRatioNextX96 = sqrtRatioTargetX96;
                } else {
                    // cap the output amount to not exceed the remaining output amount
                    amountOut = uint256(amountRemaining);
                    sqrtRatioNextX96 =
                        SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtRatioCurrentX96, liquidity, amountOut, zeroForOne);
                }
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
                // `feePips` cannot be `MAX_FEE_PIPS` for exact out
                feeAmount = FullMath.mulDivRoundingUp(amountIn, _feePips, MAX_FEE_PIPS - _feePips);
            }
        }
    }
}
