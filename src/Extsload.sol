// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/// @notice This code is adapted from
// https://github.com/RageTrade/core/blob/main/contracts/utils/Extsload.sol

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Allows the inheriting contract make it's state accessable to other contracts
/// https://ethereum-magicians.org/t/extsload-opcode-proposal/2410/11
abstract contract Extsload is IExtsload {
    /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32) {
        assembly ("memory-safe") {
            mstore(0, sload(slot))
            return(0, 0x20)
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        // since the function is external and enters a new call context and exits right
        // after execution, Solidity's memory management convention can be disregarded
        // and a direct slice of memory can be returned
        assembly ("memory-safe") {
            // Copy the abi offset of dynamic array and the length of the array to memory.
            calldatacopy(0, 0x04, 0x40)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let end := add(0x40, shl(5, slots.length))
            let calldataptr := slots.offset
            // Return values will start at 64 while calldata offset is 68.
            for { let memptr := 0x40 } 1 {} {
                mstore(memptr, sload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            // The end offset is also the length of the returndata.
            return(0, end)
        }
    }
}
