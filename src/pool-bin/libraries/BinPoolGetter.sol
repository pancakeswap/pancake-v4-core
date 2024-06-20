// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {PoolId} from "../../types/PoolId.sol";
import {BinPool} from "./BinPool.sol";
import {IBinPoolManager} from "../interfaces/IBinPoolManager.sol";
import {PackedUint128Math} from "./math/PackedUint128Math.sol";
import {BinPosition} from "./BinPosition.sol";

// forge inspect BinPoolManager storage --pretty
// | Name                  | Type                                    | Slot | Offset | Bytes | Contract                                       |
// |-----------------------|-----------------------------------------|------|--------|-------|------------------------------------------------|
// | _owner                | address                                 | 0    | 0      | 20    | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | _paused               | bool                                    | 0    | 20     | 1     | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | hasPausableRole       | mapping(address => bool)                | 1    | 0      | 32    | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | protocolFeesAccrued   | mapping(Currency => uint256)            | 2    | 0      | 32    | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | protocolFeeController | contract IProtocolFeeController         | 3    | 0      | 20    | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | MAX_BIN_STEP          | uint16                                  | 3    | 20     | 2     | src/pool-bin/BinPoolManager.sol:BinPoolManager |
// | pools                 | mapping(PoolId => struct BinPool.State) | 4    | 0      | 32    | src/pool-bin/BinPoolManager.sol:BinPoolManager |

contract BinPoolGetter {
    using BinPool for BinPool.State;

    IBinPoolManager public manager;

    uint256 constant POOLS_SLOT = 4;

    constructor(IBinPoolManager _manager) {
        manager = _manager;
    }

    function getSlot0(PoolId id) external view returns (uint24 activeId, uint24 protocolFee, uint24 lpFee) {
        // BinPool.State storage pool = manager.pools[id];
        bytes32 slot = keccak256(abi.encodePacked(id, POOLS_SLOT));
        bytes32 value = manager.extsload(slot);

        // Slot0 struct for pool state
        // struct Slot0 {
        //     uint24 activeId;
        //     uint24 protocolFee;
        //     uint24 lpFee;
        // }
        assembly ("memory-safe") {
            activeId := and(value, 0xFFFFFF)
            protocolFee := shr(24, and(value, 0xFFFFFF000000))
            lpFee := shr(48, and(value, 0xFFFFFF000000000000))
        }
    }

    function getBin(PoolId id, uint24 binId) external view returns (uint128 binReserveX, uint128 binReserveY) {
        // (binReserveX, binReserveY) = pools[id].getBin(binId);
        // BinPool.State storage pool = manager.pools[id];
        bytes32 poolStateSlot = keccak256(abi.encodePacked(id, POOLS_SLOT));

        // (binReserveX, binReserveY) = self.reserveOfBin[id].decode();
        // struct State {
        //     Slot0 slot0;
        //     mapping(uint256 binId => bytes32 reserve) reserveOfBin;
        //     mapping(uint256 binId => uint256 share) shareOfBin;
        //     mapping(bytes32 => BinPosition.Info) positions;
        //     bytes32 level0;
        //     mapping(bytes32 => bytes32) level1;
        //     mapping(bytes32 => bytes32) level2;
        // }
        bytes32 slot = keccak256(abi.encodePacked(uint256(binId), uint256(poolStateSlot) + 1));
        bytes32 value = manager.extsload(slot);
        return PackedUint128Math.decode(value);
    }

    function getPosition(PoolId id, address owner, uint24 binId, bytes32 salt)
        external
        view
        returns (BinPosition.Info memory position)
    {
        // pools[id].positions.get(owner, binId, salt);
        // BinPool.State storage pool = manager.pools[id];
        bytes32 poolStateSlot = keccak256(abi.encodePacked(id, POOLS_SLOT));

        bytes32 key;
        // still memory-safe because we've cleared the data that is out of scratch space range
        // make use of memory scratch space
        // ref: https://github.com/Vectorized/solady/blob/main/src/tokens/ERC20.sol#L95
        // memory will be 12 bytes of zeros, the 20 bytes of address, 3 bytes for uint24
        assembly ("memory-safe") {
            mstore(0x23, salt)
            mstore(0x03, binId)
            mstore(0x00, owner)
            key := keccak256(0x0c, 0x37)
            // 0x00 - 0x3f is scratch space
            // 0x40 ~ 0x46 should be clear to avoid polluting free pointer
            mstore(0x23, 0)
        }

        // struct State {
        //     Slot0 slot0;
        //     mapping(uint256 binId => bytes32 reserve) reserveOfBin;
        //     mapping(uint256 binId => uint256 share) shareOfBin;
        //     mapping(bytes32 => BinPosition.Info) positions;
        //     bytes32 level0;
        //     mapping(bytes32 => bytes32) level1;
        //     mapping(bytes32 => bytes32) level2;
        // }
        bytes32 slot = keccak256(abi.encodePacked(key, uint256(poolStateSlot) + 3));
        position.share = uint256(manager.extsload(slot));
    }
}
