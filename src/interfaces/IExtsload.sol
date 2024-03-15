//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title This is an interface to read contract's state that supports extsload.
interface IExtsload {
    /// @notice Returns a value from the storage.
    /// @param slot to read from.
    /// @return value stored at the slot.
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice Returns multiple values from storage.
    /// @param slots to read from.
    /// @return values stored at the slots.
    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory);
}
