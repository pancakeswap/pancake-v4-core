// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {IPausableRole} from "./interfaces/IPausableRole.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Allow owner and multiple accounts to pause but only owner can unpause
/// @dev Potentially allow security partners to programatically pause()
abstract contract PausableRole is IPausableRole, Ownable, Pausable {
    constructor() Ownable(msg.sender) {}

    function pause() public override onlyOwner {
        _pause();
    }

    function unpause() public override onlyOwner {
        _unpause();
    }
}
