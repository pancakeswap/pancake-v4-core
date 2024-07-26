//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPausableRole {
    /// @notice Thrown when the caller does not have the pausable role or is not owner
    error NoPausableRole();

    event PausableRoleGranted(address indexed account);
    event PausableRoleRevoked(address indexed account);

    /// @notice Pause the contract, called by the owner or an account with the pausable role
    function pause() external;

    /// @notice Unpause the contract, called by the owner
    function unpause() external;

    /// @notice Grant the pausable role to an account, called by the owner
    function grantPausableRole(address account) external;

    /// @notice Revoke the pausable role to an account, called by the owner
    function revokePausableRole(address account) external;
}
