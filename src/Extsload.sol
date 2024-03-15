// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

/// @notice This code is adapted from
// https://github.com/RageTrade/core/blob/main/contracts/utils/Extsload.sol

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Allows the inheriting contract make it's state accessable to other contracts
/// https://ethereum-magicians.org/t/extsload-opcode-proposal/2410/11
abstract contract Extsload is IExtsload {
    function extsload(bytes32 slot) external view returns (bytes32 val) {
        assembly {
            val := sload(slot)
        }
    }

    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory) {
        assembly {
            let end := add(0x20, add(slots, mul(mload(slots), 0x20)))
            for { let pointer := add(slots, 32) } lt(pointer, end) {} {
                let value := sload(mload(pointer))
                mstore(pointer, value)
                pointer := add(pointer, 0x20)
            }
        }

        return slots;
    }
}
