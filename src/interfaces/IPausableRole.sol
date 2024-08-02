//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPausableRole {
    /// @notice Pause the contract, called by the owner
    function pause() external;

    /// @notice Unpause the contract, called by the owner
    function unpause() external;
}
