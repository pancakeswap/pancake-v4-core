// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {IPausableRole} from "./interfaces/IPausableRole.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// @notice Allow owner and multiple accounts to pause but only owner can unpause
/// @dev Potentially allow security partners to programatically pause()
abstract contract PausableRole is IPausableRole, Ownable, Pausable {
    mapping(address account => bool hasPausableRole) public hasPausableRole;

    modifier onlyPausableRoleOrOwner() {
        if (msg.sender != owner() && !hasPausableRole[msg.sender]) revert NoPausableRole();
        _;
    }

    function pause() public override onlyPausableRoleOrOwner {
        _pause();
    }

    function unpause() public override onlyOwner {
        _unpause();
    }

    function grantPausableRole(address account) public override onlyOwner {
        hasPausableRole[account] = true;
        emit PausableRoleGranted(account);
    }

    function revokePausableRole(address account) public override onlyOwner {
        hasPausableRole[account] = false;
        emit PausableRoleRevoked(account);
    }
}
