// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {BinPoolGetter} from "../../../src/pool-bin/libraries/BinPoolGetter.sol";
import {PoolId} from "../../../src/types/PoolId.sol";
import {BinPool} from "../../../src/pool-bin/libraries/BinPool.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {PackedUint128Math} from "../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {BinPosition} from "../../../src/pool-bin/libraries/BinPosition.sol";

contract BinPoolManagerX is BinPoolManager {
    using BinPool for BinPool.State;
    using BinPosition for mapping(bytes32 => BinPosition.Info);

    constructor(IVault vault, uint256 controllerGasLimit) BinPoolManager(vault, controllerGasLimit) {}

    function getSlot0(PoolId id) external view returns (uint24 activeId, uint24 protocolFee, uint24 lpFee) {
        BinPool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.activeId, slot0.protocolFee, slot0.lpFee);
    }

    function getBin(PoolId id, uint24 binId) external view returns (uint128 binReserveX, uint128 binReserveY) {
        (binReserveX, binReserveY) = PackedUint128Math.decode(pools[id].reserveOfBin[binId]);
    }

    function getPosition(PoolId id, address owner, uint24 binId, bytes32 salt)
        external
        view
        returns (BinPosition.Info memory position)
    {
        return pools[id].positions.get(owner, binId, salt);
    }

    function setSlot0(PoolId id, uint24 activeId, uint24 protocolFee, uint24 lpFee) external {
        pools[id].slot0.activeId = activeId;
        pools[id].slot0.protocolFee = protocolFee;
        pools[id].slot0.lpFee = lpFee;
    }

    function setBin(PoolId id, uint24 binId, uint128 binReserveX, uint128 binReserveY) external {
        pools[id].reserveOfBin[binId] = PackedUint128Math.encode(binReserveX, binReserveY);
    }

    function setPosition(PoolId id, address owner, uint24 binId, bytes32 salt, uint256 share) external {
        BinPosition.get(pools[id].positions, owner, binId, salt).share = share;
    }
}

contract BinPoolGetterTest is Test {
    BinPoolManagerX manager;
    BinPoolGetter getter;

    function setUp() public {
        manager = new BinPoolManagerX(IVault(makeAddr("vault")), 0);
        getter = new BinPoolGetter(manager);
    }

    function testFuzz_getSlot0(PoolId id, uint24 activeId, uint24 protocolFee, uint24 lpFee) public {
        manager.setSlot0(id, activeId, protocolFee, lpFee);

        (uint24 _activeId, uint24 _protocolFee, uint24 _lpFee) = getter.getSlot0(id);
        (uint24 __activeId, uint24 __protocolFee, uint24 __lpFee) = manager.getSlot0(id);

        // check the value has been set correctly
        assertEq(_activeId, activeId);
        assertEq(_protocolFee, protocolFee);
        assertEq(_lpFee, lpFee);

        // check new getter implementation remains consistent with legacy inline getter
        assertEq(_activeId, __activeId);
        assertEq(_protocolFee, __protocolFee);
        assertEq(_lpFee, __lpFee);
    }

    function testFuzz_getBin(PoolId id, uint24 binId, uint128 binReserveX, uint128 binReserveY) public {
        manager.setBin(id, binId, binReserveX, binReserveY);

        (uint128 _binReserveX, uint128 _binReserveY) = getter.getBin(id, binId);
        (uint128 __binReserveX, uint128 __binReserveY) = manager.getBin(id, binId);

        // check the value has been set correctly
        assertEq(_binReserveX, binReserveX);
        assertEq(_binReserveY, binReserveY);

        // check new getter implementation remains consistent with legacy inline getter
        assertEq(_binReserveX, __binReserveX);
        assertEq(_binReserveY, __binReserveY);
    }

    function testFuzz_getPosition(PoolId id, address owner, uint24 binId, bytes32 salt, uint256 share) public {
        manager.setPosition(id, owner, binId, salt, share);

        BinPosition.Info memory position = getter.getPosition(id, owner, binId, salt);
        BinPosition.Info memory _position = manager.getPosition(id, owner, binId, salt);

        // check the value has been set correctly
        assertEq(position.share, share);

        // check new getter implementation remains consistent with legacy inline getter
        assertEq(position.share, _position.share);
    }
}
