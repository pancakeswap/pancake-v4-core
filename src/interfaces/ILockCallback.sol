//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Interface for the callback executed when an address locks the vault
interface ILockCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    /// @param data The data that was passed to the call to lock
    /// @return Any data that you want to be returned from the lock call
    function lockAcquired(bytes calldata data) external returns (bytes memory);
}
