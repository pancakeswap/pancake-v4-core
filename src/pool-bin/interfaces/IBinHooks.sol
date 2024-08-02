//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "../../types/PoolKey.sol";
import {BalanceDelta} from "../../types/BalanceDelta.sol";
import {IBinPoolManager} from "./IBinPoolManager.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {BeforeSwapDelta} from "../../types/BeforeSwapDelta.sol";

uint8 constant HOOKS_BEFORE_INITIALIZE_OFFSET = 0;
uint8 constant HOOKS_AFTER_INITIALIZE_OFFSET = 1;
uint8 constant HOOKS_BEFORE_MINT_OFFSET = 2;
uint8 constant HOOKS_AFTER_MINT_OFFSET = 3;
uint8 constant HOOKS_BEFORE_BURN_OFFSET = 4;
uint8 constant HOOKS_AFTER_BURN_OFFSET = 5;
uint8 constant HOOKS_BEFORE_SWAP_OFFSET = 6;
uint8 constant HOOKS_AFTER_SWAP_OFFSET = 7;
uint8 constant HOOKS_BEFORE_DONATE_OFFSET = 8;
uint8 constant HOOKS_AFTER_DONATE_OFFSET = 9;
uint8 constant HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET = 10;
uint8 constant HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET = 11;
uint8 constant HOOKS_AFTER_MINT_RETURNS_DELTA_OFFSET = 12;
uint8 constant HOOKS_AFTER_BURN_RETURNS_DELTA_OFFSET = 13;

/// @notice The PoolManager contract decides whether to invoke specific hook by inspecting the first 16
/// bits of bytes32 PoolKey.parameters. For example a 1 bit in the first bit will cause the beforeInitialize
/// hook to be invoked.
/// @dev Should only be callable by the PoolManager.
interface IBinHooks is IHooks {
    /// @notice The hook called before the state of a pool is initialized
    /// @param sender The initial msg.sender for the initialize call
    /// @param key The key for the pool being initialized
    /// @param activeId The binId of the pool, when the value is 2 ** 23, token price is 1:1
    /// @param hookData Arbitrary data handed into the PoolManager by the initializer to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    function beforeInitialize(address sender, PoolKey calldata key, uint24 activeId, bytes calldata hookData)
        external
        returns (bytes4);

    /// @notice The hook called after the state of a pool is initialized
    /// @param sender The initial msg.sender for the initialize call
    /// @param key The key for the pool being initialized
    /// @param activeId The binId of the pool, when the value is 2 ** 23, token price is 1:1
    /// @param hookData Arbitrary data handed into the PoolManager by the initializer to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    function afterInitialize(address sender, PoolKey calldata key, uint24 activeId, bytes calldata hookData)
        external
        returns (bytes4);

    /// @notice The hook called before adding liquidity
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for adding liquidity
    /// @param hookData Arbitrary data handed into the PoolManager by the liquidty provider to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return uint24 Optionally override the lp fee, only used if four conditions are met:
    ///     1) Liquidity added to active bin in different ratio from current bin (causing an internal swap)
    ///     2) the Pool has a dynamic fee,
    ///     3) the value's override flag is set to 1 i.e. vaule & OVERRIDE_FEE_FLAG = 0x400000 != 0
    ///     4) the value is less than or equal to the maximum fee (100_000) - 10%
    function beforeMint(
        address sender,
        PoolKey calldata key,
        IBinPoolManager.MintParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, uint24);

    /// @notice The hook called after adding liquidity
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for adding liquidity
    /// @param delta The amount owed to the locker (positive) or owed to the pool (negative)
    /// @param hookData Arbitrary data handed into the PoolManager by the liquidty provider to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return BalanceDelta The hook's delta in token0 and token1.
    function afterMint(
        address sender,
        PoolKey calldata key,
        IBinPoolManager.MintParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta);

    /// @notice The hook called before removing liquidity
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for removing liquidity
    /// @param hookData Arbitrary data handed into the PoolManager by the liquidty provider to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    function beforeBurn(
        address sender,
        PoolKey calldata key,
        IBinPoolManager.BurnParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice The hook called after removing liquidity
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for removing liquidity
    /// @param delta The amount owed to the locker (positive) or owed to the pool (negative)
    /// @param hookData Arbitrary data handed into the PoolManager by the liquidty provider to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return BalanceDelta The hook's delta in token0 and token1.
    function afterBurn(
        address sender,
        PoolKey calldata key,
        IBinPoolManager.BurnParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta);

    /// @notice The hook called before a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param swapForY If true, indicate swap X for Y or if false, swap Y for X
    /// @param amountSpecified Amount of tokenX or tokenY, negative imply exactInput, positive imply exactOutput
    /// @param hookData Arbitrary data handed into the PoolManager by the swapper to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return BeforeSwapDelta The hook's delta in specified and unspecified currencies.
    /// @return uint24 Optionally override the lp fee, only used if three conditions are met:
    ///     1) the Pool has a dynamic fee,
    ///     2) the value's override flag is set to 1 i.e. vaule & OVERRIDE_FEE_FLAG = 0x400000 != 0
    ///     3) the value is less than or equal to the maximum fee (100_000) - 10%
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        bool swapForY,
        int128 amountSpecified,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24);

    /// @notice The hook called after a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param swapForY If true, indicate swap X for Y or if false, swap Y for X
    /// @param amountSpecified Amount of tokenX or tokenY, negative imply exactInput, positive imply exactOutput
    /// @param delta The amount owed to the locker or owed to the pool
    /// @param hookData Arbitrary data handed into the PoolManager by the swapper to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return int128 The hook's delta in unspecified currency
    function afterSwap(
        address sender,
        PoolKey calldata key,
        bool swapForY,
        int128 amountSpecified,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);

    /// @notice The hook called before donate
    /// @param sender The initial msg.sender for the donate call
    /// @param key The key for the pool
    /// @param amount0 The amount of token0 being donated
    /// @param amount1 The amount of token1 being donated
    /// @param hookData Arbitrary data handed into the PoolManager by the donor to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice The hook called after donate
    /// @param sender The initial msg.sender for the donate call
    /// @param key The key for the pool
    /// @param amount0 The amount of token0 being donated
    /// @param amount1 The amount of token1 being donated
    /// @param hookData Arbitrary data handed into the PoolManager by the donor to be be passed on to the hook
    /// @return bytes4 The function selector for the hook
    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);
}
