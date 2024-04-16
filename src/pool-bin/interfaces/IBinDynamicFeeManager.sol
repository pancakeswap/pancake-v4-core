//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../../types/PoolKey.sol";
import {IBinPoolManager} from "./IBinPoolManager.sol";

/// @notice The dynamic fee manager determines swap fees for pools
/// @dev note that this pool is only called if the PoolKey.fee has dynamic fee flag set.
interface IBinDynamicFeeManager {
    /// @notice Called whenever BinPoolManager getSwapIn or getSwapOut is called
    /// @dev getSwapIn or getSwapOut was added to allow on-chain quotes for integrators
    /// @param amountIn either amountIn or amountOut will be non-zero, if amountIn non-zero, imply a swap with amountIn
    /// @param amountOut either amountIn or amountOut will be non-zero, if amountOut non-zero, imply a swap with amountOut
    /// @return swapFee 10_000 represent 1%, 3_000 represent 0.3%
    function getFeeForSwapInSwapOut(
        address sender,
        PoolKey calldata key,
        bool swapForY,
        uint128 amountIn,
        uint128 amountOut
    ) external view returns (uint24);
}
