// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {CLPosition} from "./CLPosition.sol";
import {TickMath} from "./TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../../types/BalanceDelta.sol";
import {Tick} from "./Tick.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {SafeCast} from "../../libraries/SafeCast.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {UnsafeMath} from "../../libraries/math/UnsafeMath.sol";
import {SwapMath} from "./SwapMath.sol";
import {LiquidityMath} from "./LiquidityMath.sol";
import {ProtocolFeeLibrary} from "../../libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";

/// @notice a library with all actions that can be performed on cl pool
library CLPool {
    using SafeCast for int256;
    using SafeCast for uint256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using CLPosition for mapping(bytes32 => CLPosition.Info);
    using CLPosition for CLPosition.Info;
    using LiquidityMath for uint128;
    using CLPool for State;
    using ProtocolFeeLibrary for uint24;
    using ProtocolFeeLibrary for uint16;
    using LPFeeLibrary for uint24;

    /// @notice Thrown when trying to initalize an already initialized pool
    error PoolAlreadyInitialized();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when trying to swap with max lp fee and specifying an output amount
    error InvalidFeeForExactOut();

    /// @notice Thrown when sqrtPriceLimitX96 is out of range
    /// @param sqrtPriceCurrentX96 current price in the pool
    /// @param sqrtPriceLimitX96 The price limit specified by user
    error InvalidSqrtPriceLimit(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice Thrown by donate if there is currently 0 liquidity, since the fees will not go to any liquidity providers
    error NoLiquidityToReceiveFees();

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // protocol fee, expressed in hundredths of a bip
        // upper 12 bits are for 1->0, and the lower 12 are for 0->1
        // the maximum is 1000 - meaning the maximum protocol fee is 0.1%
        // the protocolFee is taken from the input first, then the lpFee is taken from the remaining input
        uint24 protocolFee;
        // used for the lp fee, either static at initialize or dynamic via hook
        uint24 lpFee;
    }

    struct State {
        Slot0 slot0;
        /// @dev accumulated lp fees
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        /// @dev current active liquidity
        uint128 liquidity;
        mapping(int24 tick => Tick.Info info) ticks;
        mapping(int16 pos => uint256 bitmap) tickBitmap;
        mapping(bytes32 positionHash => CLPosition.Info info) positions;
    }

    function initialize(State storage self, uint160 sqrtPriceX96, uint24 protocolFee, uint24 lpFee)
        internal
        returns (int24 tick)
    {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        self.slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, protocolFee: protocolFee, lpFee: lpFee});
    }

    struct ModifyLiquidityParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        // the spacing between ticks
        int24 tickSpacing;
        // used to distinguish positions of the same owner, at the same tick range
        bytes32 salt;
    }

    /// @dev Effect changes to the liquidity of a position in a pool
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return delta the deltas from liquidity changes
    /// @return feeDelta the delta of the fees generated in the liquidity range
    function modifyLiquidity(State storage self, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta, BalanceDelta feeDelta)
    {
        int24 tickLower = params.tickLower;
        int24 tickUpper = params.tickUpper;
        Tick.checkTicks(tickLower, tickUpper);

        int24 tick = self.slot0.tick;
        (uint256 feesOwed0, uint256 feesOwed1) = _updatePosition(self, params, tick);

        ///@dev calculate the tokens delta needed
        int128 liquidityDelta = params.liquidityDelta;
        if (liquidityDelta != 0) {
            uint160 sqrtPriceX96 = self.slot0.sqrtPriceX96;
            int128 amount0;
            int128 amount1;
            if (tick < tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
                ).toInt128();
            } else if (tick < tickUpper) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
                ).toInt128();
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower), sqrtPriceX96, liquidityDelta
                ).toInt128();

                self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
                ).toInt128();
            }

            // Amount required for updating liquidity
            delta = toBalanceDelta(amount0, amount1);
        }

        // Fees earned from LPing are removed from the pool balance and returned separately
        feeDelta = toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the swapFee (the total percentage charged within a swap, including the protocol fee and the LP fee)
        uint24 swapFee;
        // the single direction protocol fee for the swap
        uint16 protocolFee;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // amount of input token paid as protocol fee
        uint256 feeAmountToProtocol;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    struct SwapParams {
        int24 tickSpacing;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        uint24 lpFeeOverride;
    }

    function swap(State storage self, SwapParams memory params)
        internal
        returns (BalanceDelta balanceDelta, SwapState memory state)
    {
        // cache variables for gas optimization
        Slot0 memory slot0Start = self.slot0;
        bool zeroForOne = params.zeroForOne;
        uint160 sqrtPriceLimitX96 = params.sqrtPriceLimitX96;

        // check price limit
        if (
            zeroForOne
                ? (sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96 || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO)
                : (sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96 || sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO)
        ) {
            revert InvalidSqrtPriceLimit(slot0Start.sqrtPriceX96, sqrtPriceLimitX96);
        }

        // cache variables for gas optimization
        // liquidity at the beginning of the swap
        uint128 liquidityStart = self.liquidity;
        bool exactInput = params.amountSpecified < 0;

        // init swap state
        {
            uint16 protocolFee =
                zeroForOne ? slot0Start.protocolFee.getZeroForOneFee() : slot0Start.protocolFee.getOneForZeroFee();

            uint24 lpFee = params.lpFeeOverride.isOverride()
                ? params.lpFeeOverride.removeOverrideAndValidate(LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE)
                : slot0Start.lpFee;

            state = SwapState({
                amountSpecifiedRemaining: params.amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                swapFee: protocolFee == 0 ? lpFee : protocolFee.calculateSwapFee(lpFee),
                protocolFee: protocolFee,
                feeGrowthGlobalX128: zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
                feeAmountToProtocol: 0,
                liquidity: liquidityStart
            });
        }

        /// @dev If amountSpecified is the output, also given amountSpecified cant be 0,
        /// then the tx will always revert if the swap fee is 100%
        if (state.swapFee == LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE) {
            if (!exactInput) {
                revert InvalidFeeForExactOut();
            }
        }

        /// @notice early return if hook has updated amountSpecified to 0
        if (params.amountSpecified == 0) return (BalanceDeltaLibrary.ZERO_DELTA, state);

        StepComputations memory step;
        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                self.tickBitmap.nextInitializedTickWithinOneWord(state.tick, params.tickSpacing, zeroForOne);

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, sqrtPriceLimitX96),
                state.liquidity,
                state.amountSpecifiedRemaining,
                state.swapFee
            );

            if (exactInput) {
                /// @dev SwapMath will always ensure that amountSpecified > amountIn + feeAmount
                unchecked {
                    state.amountSpecifiedRemaining += (step.amountIn + step.feeAmount).toInt256();
                }

                /// @dev amountCalculated is the amount of output token, hence neg in this case
                state.amountCalculated += step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining -= step.amountOut.toInt256();
                }
                state.amountCalculated -= (step.amountIn + step.feeAmount).toInt256();
            }

            /// @dev if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (state.protocolFee > 0) {
                unchecked {
                    // protocol fee is charged on input token first
                    uint256 delta =
                        (step.amountIn + step.feeAmount) * state.protocolFee / ProtocolFeeLibrary.PIPS_DENOMINATOR;

                    // subtract it from the total fee then left over is the LP fee
                    step.feeAmount -= delta;
                    state.feeAmountToProtocol += delta;
                }
            }

            // update global fee tracker
            if (state.liquidity > 0) {
                unchecked {
                    state.feeGrowthGlobalX128 +=
                        UnsafeMath.simpleMulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
                }
            }

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    int128 liquidityNet = self.ticks.cross(
                        step.tickNext,
                        (zeroForOne ? state.feeGrowthGlobalX128 : self.feeGrowthGlobal0X128),
                        (zeroForOne ? self.feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    state.liquidity = state.liquidity.addDelta(liquidityNet);
                }

                unchecked {
                    state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // update tick and price if changed
        if (state.tick != slot0Start.tick) {
            (self.slot0.sqrtPriceX96, self.slot0.tick) = (state.sqrtPriceX96, state.tick);
        } else {
            // otherwise just update the price
            self.slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        if (liquidityStart != state.liquidity) self.liquidity = state.liquidity;

        // update fee growth global
        if (zeroForOne) {
            self.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            self.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        unchecked {
            (int128 amount0, int128 amount1) = zeroForOne == exactInput
                ? ((params.amountSpecified - state.amountSpecifiedRemaining).toInt128(), state.amountCalculated.toInt128())
                : (
                    (state.amountCalculated.toInt128()),
                    (params.amountSpecified - state.amountSpecifiedRemaining).toInt128()
                );

            balanceDelta = toBalanceDelta(amount0, amount1);
        }
    }

    struct UpdatePositionCache {
        bool flippedLower;
        bool flippedUpper;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 feesOwed0;
        uint256 feesOwed1;
        uint128 maxLiquidityPerTick;
    }

    function _updatePosition(State storage self, ModifyLiquidityParams memory params, int24 tick)
        internal
        returns (uint256, uint256)
    {
        //@dev avoid stack too deep
        UpdatePositionCache memory cache;
        {
            uint256 _feeGrowthGlobal0X128 = self.feeGrowthGlobal0X128; // SLOAD for gas optimization
            uint256 _feeGrowthGlobal1X128 = self.feeGrowthGlobal1X128; // SLOAD for gas optimization

            ///@dev  update ticks if nencessary
            if (params.liquidityDelta != 0) {
                cache.maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                cache.flippedLower = self.ticks.update(
                    params.tickLower,
                    tick,
                    params.liquidityDelta,
                    _feeGrowthGlobal0X128,
                    _feeGrowthGlobal1X128,
                    false,
                    cache.maxLiquidityPerTick
                );
                cache.flippedUpper = self.ticks.update(
                    params.tickUpper,
                    tick,
                    params.liquidityDelta,
                    _feeGrowthGlobal0X128,
                    _feeGrowthGlobal1X128,
                    true,
                    cache.maxLiquidityPerTick
                );

                if (cache.flippedLower) {
                    self.tickBitmap.flipTick(params.tickLower, params.tickSpacing);
                }
                if (cache.flippedUpper) {
                    self.tickBitmap.flipTick(params.tickUpper, params.tickSpacing);
                }
            }

            (cache.feeGrowthInside0X128, cache.feeGrowthInside1X128) = self.ticks.getFeeGrowthInside(
                params.tickLower, params.tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128
            );
        }

        ///@dev update user position and collect fees
        /// must be done after ticks are updated in case of a 0 -> 1 flip
        (cache.feesOwed0, cache.feesOwed1) = self.positions.get(
            params.owner, params.tickLower, params.tickUpper, params.salt
        ).update(params.liquidityDelta, cache.feeGrowthInside0X128, cache.feeGrowthInside1X128);

        ///@dev clear any tick data that is no longer needed
        /// must be done after fee collection in case of a 1 -> 0 flip
        if (params.liquidityDelta < 0) {
            if (cache.flippedLower) {
                self.ticks.clear(params.tickLower);
            }
            if (cache.flippedUpper) {
                self.ticks.clear(params.tickUpper);
            }
        }

        return (cache.feesOwed0, cache.feesOwed1);
    }

    /// @notice Donates are in fact giving token to in-ranged liquidity providers only
    function donate(State storage state, uint256 amount0, uint256 amount1)
        internal
        returns (BalanceDelta delta, int24 tick)
    {
        if (state.liquidity == 0) revert NoLiquidityToReceiveFees();
        delta = toBalanceDelta(-(amount0.toInt128()), -(amount1.toInt128()));
        unchecked {
            if (amount0 > 0) {
                state.feeGrowthGlobal0X128 += UnsafeMath.simpleMulDiv(amount0, FixedPoint128.Q128, state.liquidity);
            }
            if (amount1 > 0) {
                state.feeGrowthGlobal1X128 += UnsafeMath.simpleMulDiv(amount1, FixedPoint128.Q128, state.liquidity);
            }
            tick = state.slot0.tick;
        }
    }

    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        self.checkPoolInitialized();

        self.slot0.protocolFee = protocolFee;
    }

    /// @notice Only dynamic fee pools may update the lp fee.
    function setLPFee(State storage self, uint24 lpFee) internal {
        self.checkPoolInitialized();

        self.slot0.lpFee = lpFee;
    }

    function checkPoolInitialized(State storage self) internal view {
        if (self.slot0.sqrtPriceX96 == 0) {
            // revert PoolNotInitialized();
            assembly ("memory-safe") {
                mstore(0x00, 0x486aa307)
                revert(0x1c, 0x04)
            }
        }
    }
}
