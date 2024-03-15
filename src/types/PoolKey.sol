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
    IPoolManager poolManager;
    /// @notice The pool swap fee, capped at 1_000_000. The upper 4 bits determine if the hook sets any fees.
    uint24 fee;
    /// @notice Hooks callback and pool specific parameters, i.e. tickSpacing for CL, binStep for bin
    bytes32 parameters;
}
