//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "../types/PoolKey.sol";

interface IProtocolFeeController {
    /// @notice Get the protocol fee for a pool given the conditions of this contract
    /// @param poolKey The pool key to identify the pool. The controller may want to use attributes on the pool
    ///   to determine the protocol fee, hence the entire key is needed.
    /// @return protocolFee The pool's protocol fee, expressed in hundredths of a bip.
    ///   [0 - 12[: upper bits represent protocol fee 1->0
    ///   [13 - 24[: lower 12 bits represent protocol fee for 0->1
    //    The maximum value for 1->0 and 0->1 is 1000, indication the maximum protocol fee is 0.1%.
    ///   ProtocolFee is taken from the input first, then the lpFee is taken from the remaining input
    function protocolFeeForPool(PoolKey memory poolKey) external view returns (uint24 protocolFee);
}
