// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {Ownable} from "./base/Ownable.sol";
import {Pausable} from "./base/Pausable.sol";
import {IPausable} from "./interfaces/IPausable.sol";

/// @notice Allow owner to pause in case of emergency
abstract contract Owner is Ownable, Pausable, IPausable {
    constructor() Ownable(msg.sender) {}

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }
}
