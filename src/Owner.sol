// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

// import {Ownable} from "./base/Ownable.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "./base/Pausable.sol";

/// @notice Allow owner to pause in case of emergency
abstract contract Owner is Owned, Pausable {
    constructor() Owned(msg.sender) {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
