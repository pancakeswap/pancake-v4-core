// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {ProtocolFees} from "../ProtocolFees.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {BinPool} from "./libraries/BinPool.sol";
import {BinPoolParametersHelper} from "./libraries/BinPoolParametersHelper.sol";
import {ParametersHelper} from "../libraries/math/ParametersHelper.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IBinPoolManager} from "./interfaces/IBinPoolManager.sol";
import {IBinDynamicFeeManager} from "./interfaces/IBinDynamicFeeManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {IVault} from "../interfaces/IVault.sol";
import {BinPosition} from "./libraries/BinPosition.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {PackedUint128Math} from "./libraries/math/PackedUint128Math.sol";
import {Extsload} from "../Extsload.sol";
import {BinHooks} from "./libraries/BinHooks.sol";
import {BeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import "./interfaces/IBinHooks.sol";

/// @notice Holds the state for all bin pools
contract BinPoolManager is IBinPoolManager, ProtocolFees, Extsload {
    using PoolIdLibrary for PoolKey;
    using BinPool for *;
    using BinPosition for mapping(bytes32 => BinPosition.Info);
    using BinPoolParametersHelper for bytes32;
    using LPFeeLibrary for uint24;
    using PackedUint128Math for bytes32;
    using Hooks for bytes32;

    /// @inheritdoc IBinPoolManager
    uint16 public constant override MIN_BIN_STEP = 1;

    /// @inheritdoc IBinPoolManager
    uint16 public override MAX_BIN_STEP = 100;

    mapping(PoolId id => BinPool.State) public pools;

    constructor(IVault vault, uint256 controllerGasLimit) ProtocolFees(vault, controllerGasLimit) {}

    /// @notice pool manager specified in the pool key must match current contract
    modifier poolManagerMatch(address poolManager) {
        if (address(this) != poolManager) revert PoolManagerMismatch();
        _;
    }

    function _getPool(PoolKey memory key) private view returns (BinPool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IBinPoolManager
    function getSlot0(PoolId id) external view override returns (uint24 activeId, uint24 protocolFee, uint24 lpFee) {
        BinPool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.activeId, slot0.protocolFee, slot0.lpFee);
    }

    /// @inheritdoc IBinPoolManager
    function getBin(PoolId id, uint24 binId)
        external
        view
        override
        returns (uint128 binReserveX, uint128 binReserveY)
    {
        (binReserveX, binReserveY) = pools[id].getBin(binId);
    }

    /// @inheritdoc IBinPoolManager
    function getPosition(PoolId id, address owner, uint24 binId, bytes32 salt)
        external
        view
        override
        returns (BinPosition.Info memory position)
    {
        return pools[id].positions.get(owner, binId, salt);
    }

    /// @inheritdoc IBinPoolManager
    function getNextNonEmptyBin(PoolId id, bool swapForY, uint24 binId)
        external
        view
        override
        returns (uint24 nextId)
    {
        nextId = pools[id].getNextNonEmptyBin(swapForY, binId);
    }

    /// @inheritdoc IBinPoolManager
    function initialize(PoolKey memory key, uint24 activeId, bytes calldata hookData)
        external
        override
        poolManagerMatch(address(key.poolManager))
    {
        uint16 binStep = key.parameters.getBinStep();
        if (binStep < MIN_BIN_STEP) revert BinStepTooSmall();
        if (binStep > MAX_BIN_STEP) revert BinStepTooLarge();
        if (key.currency0 >= key.currency1) revert CurrenciesInitializedOutOfOrder();

        ParametersHelper.checkUnusedBitsAllZero(
            key.parameters, BinPoolParametersHelper.OFFSET_MOST_SIGNIFICANT_UNUSED_BITS
        );
        Hooks.validateHookConfig(key);
        BinHooks.validatePermissionsConflict(key);

        /// @notice init value for dynamic lp fee is 0, but hook can still set it in afterInitialize
        uint24 lpFee = key.fee.getInitialLPFee();
        lpFee.validate(LPFeeLibrary.TEN_PERCENT_FEE);

        BinHooks.beforeInitialize(key, activeId, hookData);

        PoolId id = key.toId();

        (, uint24 protocolFee) = _fetchProtocolFee(key);
        pools[id].initialize(activeId, protocolFee, lpFee);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Initialize(id, key.currency0, key.currency1, key.fee, binStep, key.hooks);

        BinHooks.afterInitialize(key, activeId, hookData);
    }

    /// @inheritdoc IBinPoolManager
    function swap(PoolKey memory key, bool swapForY, uint128 amountIn, bytes calldata hookData)
        external
        override
        whenNotPaused
        returns (BalanceDelta delta)
    {
        if (amountIn == 0) revert InsufficientAmountIn();

        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        (uint128 amountToSwap, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride) =
            BinHooks.beforeSwap(key, swapForY, amountIn, hookData);

        /// @dev fix stack too deep
        {
            BinPool.SwapState memory state;
            (delta, state) = pool.swap(
                BinPool.SwapParams({
                    swapForY: swapForY,
                    binStep: key.parameters.getBinStep(),
                    lpFeeOverride: lpFeeOverride
                }),
                amountToSwap
            );

            unchecked {
                if (state.feeForProtocol > 0) {
                    protocolFeesAccrued[key.currency0] += state.feeForProtocol.decodeX();
                    protocolFeesAccrued[key.currency1] += state.feeForProtocol.decodeY();
                }
            }

            /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
            emit Swap(
                id, msg.sender, delta.amount0(), delta.amount1(), state.activeId, state.swapFee, state.protocolFee
            );
        }

        BalanceDelta hookDelta;
        (delta, hookDelta) = BinHooks.afterSwap(key, swapForY, amountIn, delta, hookData, beforeSwapDelta);

        if (hookDelta != BalanceDeltaLibrary.ZERO_DELTA) {
            vault.accountAppBalanceDelta(key, hookDelta, address(key.hooks));
        }

        vault.accountAppBalanceDelta(key, delta, msg.sender);
    }

    /// @inheritdoc IBinPoolManager
    function getSwapIn(PoolKey memory key, bool swapForY, uint128 amountOut)
        external
        view
        override
        returns (uint128 amountIn, uint128 amountOutLeft, uint128 fee)
    {
        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        uint24 lpFee;
        if (key.fee.isDynamicLPFee()) {
            lpFee = IBinDynamicFeeManager(address(key.hooks)).getFeeForSwapInSwapOut(
                msg.sender, key, swapForY, 0, amountOut
            );
        } else {
            lpFee = key.fee.getInitialLPFee();
        }
        lpFee.validate(LPFeeLibrary.TEN_PERCENT_FEE);

        (amountIn, amountOutLeft, fee) = pool.getSwapIn(
            BinPool.SwapViewParams({swapForY: swapForY, binStep: key.parameters.getBinStep(), lpFee: lpFee}), amountOut
        );
    }

    /// @inheritdoc IBinPoolManager
    function getSwapOut(PoolKey memory key, bool swapForY, uint128 amountIn)
        external
        view
        override
        returns (uint128 amountInLeft, uint128 amountOut, uint128 fee)
    {
        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        uint24 lpFee;
        if (key.fee.isDynamicLPFee()) {
            lpFee =
                IBinDynamicFeeManager(address(key.hooks)).getFeeForSwapInSwapOut(msg.sender, key, swapForY, amountIn, 0);
        } else {
            lpFee = key.fee.getInitialLPFee();
        }
        lpFee.validate(LPFeeLibrary.TEN_PERCENT_FEE);

        (amountInLeft, amountOut, fee) = pool.getSwapOut(
            BinPool.SwapViewParams({swapForY: swapForY, binStep: key.parameters.getBinStep(), lpFee: lpFee}), amountIn
        );
    }

    /// @inheritdoc IBinPoolManager
    function mint(PoolKey memory key, IBinPoolManager.MintParams calldata params, bytes calldata hookData)
        external
        override
        whenNotPaused
        returns (BalanceDelta delta, BinPool.MintArrays memory mintArray)
    {
        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        BinHooks.beforeMint(key, params, hookData);

        bytes32 feeForProtocol;
        bytes32 compositionFee;
        (delta, feeForProtocol, mintArray, compositionFee) = pool.mint(
            BinPool.MintParams({
                to: msg.sender,
                liquidityConfigs: params.liquidityConfigs,
                amountIn: params.amountIn,
                binStep: key.parameters.getBinStep(),
                salt: params.salt
            })
        );

        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[key.currency0] += feeForProtocol.decodeX();
                protocolFeesAccrued[key.currency1] += feeForProtocol.decodeY();
            }
        }

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Mint(id, msg.sender, mintArray.ids, params.salt, mintArray.amounts, compositionFee, feeForProtocol);

        BalanceDelta hookDelta;
        (delta, hookDelta) = BinHooks.afterMint(key, params, delta, hookData);

        if (hookDelta != BalanceDeltaLibrary.ZERO_DELTA) {
            vault.accountAppBalanceDelta(key, hookDelta, address(key.hooks));
        }
        vault.accountAppBalanceDelta(key, delta, msg.sender);
    }

    /// @inheritdoc IBinPoolManager
    function burn(PoolKey memory key, IBinPoolManager.BurnParams memory params, bytes calldata hookData)
        external
        override
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        BinHooks.beforeBurn(key, params, hookData);

        uint256[] memory binIds;
        bytes32[] memory amountRemoved;
        (delta, binIds, amountRemoved) = pool.burn(
            BinPool.BurnParams({
                from: msg.sender,
                ids: params.ids,
                amountsToBurn: params.amountsToBurn,
                salt: params.salt
            })
        );

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Burn(id, msg.sender, binIds, params.salt, amountRemoved);

        BalanceDelta hookDelta;
        (delta, hookDelta) = BinHooks.afterBurn(key, params, delta, hookData);

        if (hookDelta != BalanceDeltaLibrary.ZERO_DELTA) {
            vault.accountAppBalanceDelta(key, hookDelta, address(key.hooks));
        }
        vault.accountAppBalanceDelta(key, delta, msg.sender);
    }

    function donate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookData)
        external
        override
        whenNotPaused
        returns (BalanceDelta delta, uint24 binId)
    {
        PoolId id = key.toId();
        BinPool.State storage pool = pools[id];
        pool.checkPoolInitialized();

        BinHooks.beforeDonate(key, amount0, amount1, hookData);

        (delta, binId) = pool.donate(key.parameters.getBinStep(), amount0, amount1);

        vault.accountAppBalanceDelta(key, delta, msg.sender);

        /// @notice Make sure the first event is noted, so that later events from afterHook won't get mixed up with this one
        emit Donate(id, msg.sender, delta.amount0(), delta.amount1(), binId);

        BinHooks.afterDonate(key, amount0, amount1, hookData);
    }

    /// @inheritdoc IBinPoolManager
    function setMaxBinStep(uint16 maxBinStep) external override onlyOwner {
        if (maxBinStep <= MIN_BIN_STEP) revert MaxBinStepTooSmall(maxBinStep);

        MAX_BIN_STEP = maxBinStep;
        emit SetMaxBinStep(maxBinStep);
    }

    /// @inheritdoc IPoolManager
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external override {
        if (!key.fee.isDynamicLPFee() || msg.sender != address(key.hooks)) revert UnauthorizedDynamicLPFeeUpdate();
        newDynamicLPFee.validate(LPFeeLibrary.TEN_PERCENT_FEE);

        PoolId id = key.toId();
        pools[id].setLPFee(newDynamicLPFee);
        emit DynamicLPFeeUpdated(id, newDynamicLPFee);
    }

    function _setProtocolFee(PoolId id, uint24 newProtocolFee) internal override {
        pools[id].setProtocolFee(newProtocolFee);
    }
}
