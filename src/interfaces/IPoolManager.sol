//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";

interface IPoolManager {
    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice PoolKey must have currencies where address(currency0) < address(currency1)
    error CurrenciesInitializedOutOfOrder();

    /// @notice Thrown when a call to updateDynamicLPFee is made by an address that is not the hook,
    /// or on a pool is not a dynamic fee pool.
    error UnauthorizedDynamicLPFeeUpdate();

    /// @notice Emitted when lp fee is updated
    /// @dev The event is emitted even if the updated fee value is the same as previous one
    event DynamicLPFeeUpdated(PoolId indexed id, uint24 dynamicLPFee);

    /// @notice Updates lp fee for a dyanmic fee pool
    /// @dev Some of the use case could be:
    ///   1) when hook#beforeSwap() is called and hook call this function to update the lp fee
    ///   2) For BinPool only, when hook#beforeMint() is called and hook call this function to update the lp fee
    ///   3) other use case where the hook might want to on an ad-hoc basis increase/reduce lp fee
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external;
}
