// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import "./interfaces/ICLHooks.sol";
import {ProtocolFees} from "../ProtocolFees.sol";
import {ICLPoolManager} from "./interfaces/ICLPoolManager.sol";
import {IVault} from "../interfaces/IVault.sol";
import {PoolId} from "../types/PoolId.sol";
import {CLPool} from "./libraries/CLPool.sol";
import {CLPosition} from "./libraries/CLPosition.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {Tick} from "./libraries/Tick.sol";
import {CLPoolParametersHelper} from "./libraries/CLPoolParametersHelper.sol";
import {ParametersHelper} from "../libraries/math/ParametersHelper.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {Extsload} from "../Extsload.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CLPoolGetters} from "./libraries/CLPoolGetters.sol";
import {CLHooks} from "./libraries/CLHooks.sol";
import {BeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import {Currency} from "../types/Currency.sol";
import {TickMath} from "./libraries/TickMath.sol";

contract CLPoolManager is ICLPoolManager, ProtocolFees, Extsload {
    using SafeCast for int256;
    using Hooks for bytes32;
    using LPFeeLibrary for uint24;
    using CLPoolParametersHelper for bytes32;
    using CLPool for *;
    using CLPosition for mapping(bytes32 => CLPosition.Info);
    using CLPoolGetters for CLPool.State;

    mapping(PoolId id => CLPool.State poolState) private pools;

    mapping(PoolId id => PoolKey poolKey) public poolIdToPoolKey;

    constructor(IVault _vault) ProtocolFees(_vault) {}

    /// @notice pool manager specified in the pool key must match current contract
    modifier poolManagerMatch(address poolManager) {
        if (address(this) != poolManager) revert PoolManagerMismatch();
        _;
    }

    /// @inheritdoc ICLPoolManager
    function getSlot0(PoolId id)
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        CLPool.Slot0 memory slot0 = pools[id].slot0;
        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee, slot0.lpFee);
    }

    /// @inheritdoc ICLPoolManager
    function getLiquidity(PoolId id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @inheritdoc ICLPoolManager
    function getLiquidity(PoolId id, address _owner, int24 tickLower, int24 tickUpper, bytes32 salt)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[id].positions.get(_owner, tickLower, tickUpper, salt).liquidity;
    }

    /// @inheritdoc ICLPoolManager
    function getPosition(PoolId id, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
        external
        view
        override
        returns (CLPosition.Info memory position)
    {
        return pools[id].positions.get(owner, tickLower, tickUpper, salt);
    }

    /// @inheritdoc ICLPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        poolManagerMatch(address(key.poolManager))
        returns (int24 tick)
    {
        int24 tickSpacing = key.parameters.getTickSpacing();
        if (tickSpacing > TickMath.MAX_TICK_SPACING) revert TickSpacingTooLarge(tickSpacing);
        if (tickSpacing < TickMath.MIN_TICK_SPACING) revert TickSpacingTooSmall(tickSpacing);
        if (key.currency0 >= key.currency1) {
            revert CurrenciesInitializedOutOfOrder(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
        }

        ParametersHelper.checkUnusedBitsAllZero(
            key.parameters, CLPoolParametersHelper.OFFSET_MOST_SIGNIFICANT_UNUSED_BITS
        );
        Hooks.validateHookConfig(key);
        CLHooks.validatePermissionsConflict(key);

        /// @notice init value for dynamic lp fee is 0, but hook can still set it in afterInitialize
        uint24 lpFee = key.fee.getInitialLPFee();
        lpFee.validate(LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE);

        CLHooks.beforeInitialize(key, sqrtPriceX96, hookData);

        PoolId id = key.toId();
        (, uint24 protocolFee) = _fetchProtocolFee(key);
        tick = pools[id].initialize(sqrtPriceX96, protocolFee, lpFee);

        poolIdToPoolKey[id] = key;

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Initialize(id, key.currency0, key.currency1, key.hooks, key.fee, key.parameters, sqrtPriceX96, tick);

        CLHooks.afterInitialize(key, sqrtPriceX96, tick, hookData);
    }

    /// @inheritdoc ICLPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external override returns (BalanceDelta delta, BalanceDelta feeDelta) {
        // Do not allow add liquidity when paused()
        if (paused() && params.liquidityDelta > 0) revert PoolPaused();

        PoolId id = key.toId();
        CLPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        CLHooks.beforeModifyLiquidity(key, params, hookData);

        (delta, feeDelta) = pool.modifyLiquidity(
            CLPool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.parameters.getTickSpacing(),
                salt: params.salt
            })
        );

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta, params.salt);

        BalanceDelta hookDelta;
        // notice that both generated delta and feeDelta (from lpFee) will both be counted on the user
        (delta, hookDelta) = CLHooks.afterModifyLiquidity(key, params, delta + feeDelta, feeDelta, hookData);

        if (hookDelta != BalanceDeltaLibrary.ZERO_DELTA) {
            vault.accountAppBalanceDelta(key.currency0, key.currency1, hookDelta, address(key.hooks));
        }
        vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, msg.sender);
    }

    /// @inheritdoc ICLPoolManager
    function swap(PoolKey memory key, ICLPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        whenNotPaused
        returns (BalanceDelta delta)
    {
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();

        PoolId id = key.toId();
        CLPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        (int256 amountToSwap, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride) =
            CLHooks.beforeSwap(key, params, hookData);
        CLPool.SwapState memory state;
        (delta, state) = pool.swap(
            CLPool.SwapParams({
                tickSpacing: key.parameters.getTickSpacing(),
                zeroForOne: params.zeroForOne,
                amountSpecified: amountToSwap,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                lpFeeOverride: lpFeeOverride
            })
        );

        unchecked {
            if (state.feeAmountToProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += state.feeAmountToProtocol;
            }
        }

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Swap(
            id,
            msg.sender,
            delta.amount0(),
            delta.amount1(),
            state.sqrtPriceX96,
            state.liquidity,
            state.tick,
            state.swapFee,
            state.protocolFee
        );

        BalanceDelta hookDelta;
        (delta, hookDelta) = CLHooks.afterSwap(key, params, delta, hookData, beforeSwapDelta);

        if (hookDelta != BalanceDeltaLibrary.ZERO_DELTA) {
            vault.accountAppBalanceDelta(key.currency0, key.currency1, hookDelta, address(key.hooks));
        }

        /// @dev delta already includes protocol fee
        /// all tokens go into the vault
        vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, msg.sender);
    }

    /// @inheritdoc ICLPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        whenNotPaused
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        CLPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        CLHooks.beforeDonate(key, amount0, amount1, hookData);

        int24 tick;
        (delta, tick) = pool.donate(amount0, amount1);
        vault.accountAppBalanceDelta(key.currency0, key.currency1, delta, msg.sender);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Donate(id, msg.sender, amount0, amount1, tick);

        CLHooks.afterDonate(key, amount0, amount1, hookData);
    }

    function getPoolTickInfo(PoolId id, int24 tick) external view returns (Tick.Info memory) {
        return pools[id].getPoolTickInfo(tick);
    }

    function getPoolBitmapInfo(PoolId id, int16 word) external view returns (uint256 tickBitmap) {
        return pools[id].getPoolBitmapInfo(word);
    }

    function getFeeGrowthGlobals(PoolId id)
        external
        view
        returns (uint256 feeGrowthGlobal0x128, uint256 feeGrowthGlobal1x128)
    {
        return pools[id].getFeeGrowthGlobals();
    }

    /// @inheritdoc IPoolManager
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external override {
        if (!key.fee.isDynamicLPFee() || msg.sender != address(key.hooks)) revert UnauthorizedDynamicLPFeeUpdate();
        newDynamicLPFee.validate(LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE);

        PoolId id = key.toId();
        pools[id].setLPFee(newDynamicLPFee);
        emit DynamicLPFeeUpdated(id, newDynamicLPFee);
    }

    function _setProtocolFee(PoolId id, uint24 newProtocolFee) internal override {
        pools[id].setProtocolFee(newProtocolFee);
    }

    /// @notice not accept ether
    // receive() external payable {}
    // fallback() external payable {}
}
