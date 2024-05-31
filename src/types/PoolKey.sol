//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "./Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";

/// @notice Returns the key for identifying a pool
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @notice The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @notice The hooks of the pool, won't have a general interface because hooks interface vary on pool type
    IHooks hooks;
    /// @notice The pool manager of the pool
    /// @dev will remove the pool manager from the pool key, will add a poolManager ID into parameters
    // IPoolManager poolManager;
    /// @notice The pool lp fee, capped at 1_000_000. If the pool has a dynamic fee then it must be exactly equal to 0x800000
    /// uint24 fee; put this into parameters
    /// @notice Hooks callback and pool specific parameters, i.e. tickSpacing for CL, binStep for bin
    /**
     * [0 - 16[: hooks registration bitmaps
     * [16 - 39[: tickSpacing (24 bits) for CL,
     * [16 - 31[: binSteps (16 bits) for bin
     * [40- 63 [: fee (24 bits)}
     * [64 - 73 [: poolManager ID (10 bits) , default CLPoolManager is 1 , binPoolManager is 2
     */
    bytes32 parameters;
}
