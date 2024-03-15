//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";

interface IPoolManager {
    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice PoolKey must have currencies where address(currency0) < address(currency1)
    error CurrenciesInitializedOutOfOrder();

    /// @notice Emitted when protocol fee is updated
    /// @dev The event is emitted even if the updated protocolFee is the same as previous protocolFee
    event ProtocolFeeUpdated(PoolId indexed id, uint16 protocolFee);

    /// @notice Emitted when swap fee is updated
    /// @dev The event is emitted even if the updated swap fee is the same as previous swap fee
    event DynamicSwapFeeUpdated(PoolId indexed id, uint24 dynamicSwapFee);

    /// @notice Sets the protocol's swap fee for the given pool
    /// Protocol fee is always a portion of swap fee that is owed. If that underlying fee is 0, no protocol fee will accrue even if it is set to > 0.
    function setProtocolFee(PoolKey memory key) external;

    /// @notice Updates the pools swap fee for the a pool that has enabled dynamic swap fee.
    /// @dev Some of the use case could be:
    ///   1) when hook#beforeSwap() is called and hook call this function to update the swap fee
    ///   2) For BinPool only, when hook#beforeMint() is called and hook call this function to update the swap fee
    ///   3) other use case where the hook might want to on an ad-hoc basis increase/reduce swap fee
    function updateDynamicSwapFee(PoolKey memory key) external;
}
