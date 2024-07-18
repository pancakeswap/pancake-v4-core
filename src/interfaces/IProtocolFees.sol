//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "../types/Currency.sol";
import {IProtocolFeeController} from "./IProtocolFeeController.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IVault} from "./IVault.sol";

interface IProtocolFees {
    /// @notice Thrown when the protocol fee exceeds the upper limit.
    error ProtocolFeeTooLarge(uint24 fee);
    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();
    /// @notice Thrown when user not authorized to set or collect protocol fee
    error InvalidCaller();

    /// @notice Emitted when protocol fee is updated
    /// @dev The event is emitted even if the updated protocolFee is the same as previous protocolFee
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);

    /// @notice Emitted when the protocol fee controller is updated
    event ProtocolFeeControllerUpdated(address protocolFeeController);

    /// @notice Given a currency address, returns the protocol fees accrued in that currency
    function protocolFeesAccrued(Currency) external view returns (uint256);

    /// @notice Returns the current protocol fee controller address
    /// @return IProtocolFeeController The currency protocol fee controller
    function protocolFeeController() external view returns (IProtocolFeeController);

    /// @notice Sets the protocol's swap fee for the given pool
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external;

    /// @notice Update the protocol fee controller, called by the owner
    function setProtocolFeeController(IProtocolFeeController controller) external;

    /// @notice Collects the protocol fee accrued in the given currency, called by the owner or the protocol fee controller
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected);

    /// @notice Returns the vault where the protocol fees are safely stored
    /// @return IVault The address of the vault
    function vault() external view returns (IVault);
}
