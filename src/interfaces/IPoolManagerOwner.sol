//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "../types/Currency.sol";
import {IProtocolFeeController} from "./IProtocolFeeController.sol";

interface IPoolManagerOwner {
    /// @notice pause pool manager, only owner or account with pausable role can call. Once
    /// paused, no swaps, donate or add liquidity are allowed, only remove liquidity is permitted.
    /// @dev PCS will have security monitoring integration to pause the pool manager in case of any suspicious activity
    function pausePoolManager() external;

    /// @notice unpause pool manager, only owner can call
    function unpausePoolManager() external;

    /// @notice set the protocol fee controller, only owner can call
    function setProtocolFeeController(IProtocolFeeController protocolFeeController) external;

    /// @notice transfer the ownership of pool manager to the new owner
    /// @dev used when a new PoolManagerOwner contract is created and we transfer pool manager owner to new contract
    /// @param newPoolManagerOwner the address of the new owner
    function transferPoolManagerOwnership(address newPoolManagerOwner) external;

    /// @notice accept the ownership of pool manager, only callable by the
    /// pending pool manager owner set by latest transferPoolManagerOwnership
    function acceptPoolManagerOwnership() external;

    /// @notice get the current pending pool manager owner
    /// @return the address of the pending pool manager owner
    function pendingPoolManagerOwner() external view returns (address);
}
