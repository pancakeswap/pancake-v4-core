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
    /// @notice Thrown when calls to protocolFeeController fails or return size is not 32 bytes
    error ProtocolFeeCannotBeFetched();

    /// @notice Thrown when user not authorized to set or collect protocol fee
    error InvalidCaller();

    /// @notice Emitted when protocol fee is updated
    /// @dev The event is emitted even if the updated protocolFee is the same as previous protocolFee
    /// @param id The pool id for which the protocol fee is updated
    /// @param protocolFee  The new protocol fee value
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);

    /// @notice Emitted when protocol fee controller is updated
    /// @param protocolFeeController The new protocol fee controller
    event ProtocolFeeControllerUpdated(address indexed protocolFeeController);

    /// @notice Given a currency address, returns the protocol fees accrued in that currency
    /// @param currency The currency to check
    /// @return amount The amount of protocol fees accrued in the given currency
    function protocolFeesAccrued(Currency currency) external view returns (uint256 amount);

    /// @notice Returns the current protocol fee controller address
    /// @return IProtocolFeeController The currency protocol fee controller
    function protocolFeeController() external view returns (IProtocolFeeController);

    /// @notice Sets the protocol's swap fee for the given pool
    /// @param key The pool key for which to set the protocol fee
    /// @param newProtocolFee The new protocol fee to set
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external;

    /// @notice Update the protocol fee controller, called by the owner
    /// @param controller The new protocol fee controller to be set
    function setProtocolFeeController(IProtocolFeeController controller) external;

    /// @notice Collects the protocol fee accrued in the given currency, called by the owner or the protocol fee controller
    /// @dev This will revert if vault is locked
    /// @param recipient The address to which the protocol fees should be sent
    /// @param currency The currency in which to collect the protocol fees
    /// @param amount The amount of protocol fees to collect
    /// @return amountCollected The amount of protocol fees actually collected
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected);

    /// @notice Returns the vault where the protocol fees are safely stored
    /// @return IVault The address of the vault
    function vault() external view returns (IVault);
}
