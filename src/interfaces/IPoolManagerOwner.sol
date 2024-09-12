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

    /// @notice collect protocol fees, only owner can call
    function collectProtocolFees(address recipient, Currency currency, uint256 amount) external;
}
