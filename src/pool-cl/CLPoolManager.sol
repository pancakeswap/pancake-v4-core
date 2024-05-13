// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import "./interfaces/ICLHooks.sol";
import {ProtocolFees} from "../ProtocolFees.sol";
import {ICLPoolManager} from "./interfaces/ICLPoolManager.sol";
import {IVault} from "../interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {CLPool} from "./libraries/CLPool.sol";
import {CLPosition} from "./libraries/CLPosition.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {Tick} from "./libraries/Tick.sol";
import {CLPoolParametersHelper} from "./libraries/CLPoolParametersHelper.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {Extsload} from "../Extsload.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CLPoolGetters} from "./libraries/CLPoolGetters.sol";

contract CLPoolManager is ICLPoolManager, ProtocolFees, Extsload {
    using SafeCast for int256;
    using PoolIdLibrary for PoolKey;
    using Hooks for bytes32;
    using LPFeeLibrary for uint24;
    using CLPoolParametersHelper for bytes32;
    using CLPool for *;
    using CLPosition for mapping(bytes32 => CLPosition.Info);
    using CLPoolGetters for CLPool.State;

    /// @inheritdoc ICLPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc ICLPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    mapping(PoolId id => CLPool.State) public pools;

    constructor(IVault _vault, uint256 controllerGasLimit) ProtocolFees(_vault, controllerGasLimit) {}

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
    function getLiquidity(PoolId id, address _owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[id].positions.get(_owner, tickLower, tickUpper).liquidity;
    }

    /// @inheritdoc ICLPoolManager
    function getPosition(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (CLPosition.Info memory position)
    {
        return pools[id].positions.get(owner, tickLower, tickUpper);
    }

    /// @inheritdoc ICLPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        poolManagerMatch(address(key.poolManager))
        returns (int24 tick)
    {
        int24 tickSpacing = key.parameters.getTickSpacing();
        if (tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (key.currency0 >= key.currency1) revert CurrenciesInitializedOutOfOrder();

        ICLHooks hooks = ICLHooks(address(key.hooks));
        Hooks.validateHookConfig(key);
        _validateHookNoOp(key);

        /// @notice init value for dynamic lp fee is 0, but hook can still set it in afterInitialize
        uint24 lpFee = key.fee.getInitialLPFee();
        lpFee.validate(LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE);

        if (key.parameters.shouldCall(HOOKS_BEFORE_INITIALIZE_OFFSET, hooks)) {
            if (hooks.beforeInitialize(msg.sender, key, sqrtPriceX96, hookData) != ICLHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        PoolId id = key.toId();
        (, uint24 protocolFee) = _fetchProtocolFee(key);
        tick = pools[id].initialize(sqrtPriceX96, protocolFee, lpFee);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Initialize(id, key.currency0, key.currency1, key.fee, tickSpacing, hooks);

        if (key.parameters.shouldCall(HOOKS_AFTER_INITIALIZE_OFFSET, hooks)) {
            if (
                hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick, hookData)
                    != ICLHooks.afterInitialize.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc ICLPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    )
        external
        override
        poolManagerMatch(address(key.poolManager))
        returns (BalanceDelta delta, BalanceDelta feeDelta)
    {
        // Do not allow add liquidity when paused()
        if (paused() && params.liquidityDelta > 0) revert PoolPaused();

        PoolId id = key.toId();
        _checkPoolInitialized(id);

        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (params.liquidityDelta > 0 && key.parameters.shouldCall(HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET, hooks)) {
            bytes4 selector = hooks.beforeAddLiquidity(msg.sender, key, params, hookData);
            if (key.parameters.isValidNoOpCall(HOOKS_NO_OP_OFFSET, selector)) {
                // Sentinel return value used to signify that a NoOp occurred.
                return (BalanceDeltaLibrary.MAXIMUM_DELTA, BalanceDeltaLibrary.ZERO_DELTA);
            } else if (selector != ICLHooks.beforeAddLiquidity.selector) {
                revert Hooks.InvalidHookResponse();
            }
        } else if (params.liquidityDelta <= 0 && key.parameters.shouldCall(HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET, hooks))
        {
            bytes4 selector = hooks.beforeRemoveLiquidity(msg.sender, key, params, hookData);
            if (key.parameters.isValidNoOpCall(HOOKS_NO_OP_OFFSET, selector)) {
                // Sentinel return value used to signify that a NoOp occurred.
                return (BalanceDeltaLibrary.MAXIMUM_DELTA, BalanceDeltaLibrary.ZERO_DELTA);
            } else if (selector != ICLHooks.beforeRemoveLiquidity.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        (delta, feeDelta) = pools[id].modifyLiquidity(
            CLPool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.parameters.getTickSpacing()
            })
        );

        vault.accountPoolBalanceDelta(key, delta + feeDelta, msg.sender);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);

        if (params.liquidityDelta > 0 && key.parameters.shouldCall(HOOKS_AFTER_ADD_LIQUIDITY_OFFSET, hooks)) {
            if (
                hooks.afterAddLiquidity(msg.sender, key, params, delta, hookData) != ICLHooks.afterAddLiquidity.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        } else if (params.liquidityDelta <= 0 && key.parameters.shouldCall(HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET, hooks))
        {
            if (
                hooks.afterRemoveLiquidity(msg.sender, key, params, delta, hookData)
                    != ICLHooks.afterRemoveLiquidity.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc ICLPoolManager
    function swap(PoolKey memory key, ICLPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        poolManagerMatch(address(key.poolManager))
        whenNotPaused
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        ICLHooks hooks = ICLHooks(address(key.hooks));

        if (key.parameters.shouldCall(HOOKS_BEFORE_SWAP_OFFSET, hooks)) {
            bytes4 selector = hooks.beforeSwap(msg.sender, key, params, hookData);
            if (key.parameters.isValidNoOpCall(HOOKS_NO_OP_OFFSET, selector)) {
                // Sentinel return value used to signify that a NoOp occurred.
                return BalanceDeltaLibrary.MAXIMUM_DELTA;
            } else if (selector != ICLHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        CLPool.SwapState memory state;
        (delta, state) = pools[id].swap(
            CLPool.SwapParams({
                tickSpacing: key.parameters.getTickSpacing(),
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        /// @dev delta already includes protocol fee
        /// all tokens go into the vault
        vault.accountPoolBalanceDelta(key, delta, msg.sender);

        unchecked {
            if (state.feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += state.feeForProtocol;
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

        if (key.parameters.shouldCall(HOOKS_AFTER_SWAP_OFFSET, hooks)) {
            if (hooks.afterSwap(msg.sender, key, params, delta, hookData) != ICLHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc ICLPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        poolManagerMatch(address(key.poolManager))
        whenNotPaused
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        ICLHooks hooks = ICLHooks(address(key.hooks));
        if (key.parameters.shouldCall(HOOKS_BEFORE_DONATE_OFFSET, hooks)) {
            bytes4 selector = hooks.beforeDonate(msg.sender, key, amount0, amount1, hookData);
            if (key.parameters.isValidNoOpCall(HOOKS_NO_OP_OFFSET, selector)) {
                // Sentinel return value used to signify that a NoOp occurred.
                return BalanceDeltaLibrary.MAXIMUM_DELTA;
            } else if (selector != ICLHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        int24 tick;
        (delta, tick) = pools[id].donate(amount0, amount1);
        vault.accountPoolBalanceDelta(key, delta, msg.sender);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Donate(id, msg.sender, amount0, amount1, tick);

        if (key.parameters.shouldCall(HOOKS_AFTER_DONATE_OFFSET, hooks)) {
            if (hooks.afterDonate(msg.sender, key, amount0, amount1, hookData) != ICLHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
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

    function _checkPoolInitialized(PoolId id) internal view {
        if (pools[id].isNotInitialized()) revert PoolNotInitialized();
    }

    function _validateHookNoOp(PoolKey memory key) internal pure {
        // if no-op is active for hook, there must be a before* hook active too
        if (key.parameters.hasOffsetEnabled(HOOKS_NO_OP_OFFSET)) {
            if (
                !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET)
                    && !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET)
                    && !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_OFFSET)
                    && !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_DONATE_OFFSET)
            ) {
                revert Hooks.NoOpHookMissingBeforeCall();
            }
        }
    }

    /// @notice not accept ether
    // receive() external payable {}
    // fallback() external payable {}
}
