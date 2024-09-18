// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Allow owner and multiple accounts to pause but only owner can unpause
/// @dev Potentially allow security partners to programatically pause()
abstract contract PausableRole is Ownable2Step {
    /// @notice Thrown when the caller does not have the pausable role or is not owner
    error NoPausableRole();

    event PausableRoleGranted(address indexed account);
    event PausableRoleRevoked(address indexed account);

    mapping(address account => bool hasPausableRole) public hasPausableRole;

    constructor() Ownable(msg.sender) {}

    modifier onlyPausableRoleOrOwner() {
        if (msg.sender != owner() && !hasPausableRole[msg.sender]) revert NoPausableRole();
        _;
    }

    /// @notice Grant the pausable role to an account
    /// @dev Role will be granted to PCS security monitoring integration, so pause can happen the moment any suspicious activity is detected.
    function grantPausableRole(address account) public onlyOwner {
        hasPausableRole[account] = true;
        emit PausableRoleGranted(account);
    }

    function revokePausableRole(address account) public onlyOwner {
        hasPausableRole[account] = false;
        emit PausableRoleRevoked(account);
    }
}
