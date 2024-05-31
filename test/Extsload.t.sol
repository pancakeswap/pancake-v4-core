// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/Test.sol";
import {CLPoolManager} from "../src/pool-cl/CLPoolManager.sol";
import {Vault} from "../src/Vault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {ICLPoolManager} from "../src/pool-cl/interfaces/ICLPoolManager.sol";
import {IProtocolFeeController} from "../src/interfaces/IProtocolFeeController.sol";
import {Extsload} from "../src/Extsload.sol";

contract Loadable is Extsload {}

contract ExtsloadTest is Test, GasSnapshot {
    // "forge inspect src/pool-cl/CLPoolManager.sol:CLPoolManager storage --pretty" to get the storage layout below
    // | Name                  | Type                                   | Slot | Offset | Bytes | Contract                                    |
    // |-----------------------|----------------------------------------|------|--------|-------|---------------------------------------------|
    // | _owner                | address                                | 0    | 0      | 20    | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    // | _paused               | bool                                   | 0    | 20     | 1     | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    // | hasPausableRole       | mapping(address => bool)               | 1    | 0      | 32    | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    // | protocolFeesAccrued   | mapping(Currency => uint256)           | 2    | 0      | 32    | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    // | protocolFeeController | contract IProtocolFeeController        | 3    | 0      | 20    | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    // | pools                 | mapping(PoolId => struct CLPool.State) | 4    | 0      | 32    | src/pool-cl/CLPoolManager.sol:CLPoolManager |
    ICLPoolManager poolManager;

    Loadable loadable = new Loadable();

    function setUp() public {
        IVault vault = new Vault();
        poolManager = new CLPoolManager(vault, 500000);

        poolManager.setProtocolFeeController(IProtocolFeeController(address(0xabcd)));
    }

    function testExtsload() public {
        // as contract is not paused, slot0 is 0x0...0_owner_address,
        // if paused, slot0 is 0x0...1_owner_address
        snapStart("ExtsloadTest#extsload");
        bytes32 slot0 = poolManager.extsload(0x00);
        snapEnd();
        assertEq(abi.encode(slot0), abi.encode(address(this)));

        bytes32 slot3 = poolManager.extsload(bytes32(uint256(0x03)));
        assertEq(abi.encode(slot3), abi.encode(address(0xabcd)));
    }

    function testExtsloadInBatch() public {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = 0x00;
        slots[1] = bytes32(uint256(0x03));
        snapStart("ExtsloadTest#extsloadInBatch");
        slots = poolManager.extsload(slots);
        snapEnd();

        assertEq(abi.encode(slots[0]), abi.encode(address(this)));
        assertEq(abi.encode(slots[1]), abi.encode(address(0xabcd)));
    }

    function testExtsload_10_sparse() public {
        bytes32[] memory keys = new bytes32[](10);
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = keccak256(abi.encode(i));
            vm.store(address(loadable), keys[i], bytes32(i));
        }

        bytes32[] memory values = loadable.extsload(keys);
        assertEq(values.length, keys.length);
        for (uint256 i = 0; i < values.length; i++) {
            assertEq(values[i], bytes32(i));
        }
    }

    function testFuzz_extsload(uint256 length, uint256 seed, bytes memory dirtyBits) public {
        length = bound(length, 0, 1000);

        bytes32[] memory slots = new bytes32[](length);
        bytes32[] memory expected = new bytes32[](length);
        for (uint256 i; i < length; ++i) {
            slots[i] = keccak256(abi.encode(i, seed));
            expected[i] = keccak256(abi.encode(slots[i]));
            vm.store(address(loadable), slots[i], expected[i]);
        }
        bytes32[] memory values = loadable.extsload(slots);
        // assertEq(values, expected); //todo: uncomment once bumped forge-std lib

        // test with dirty bits
        bytes memory data = abi.encodeWithSignature("extsload(bytes32[])", (slots));
        bytes memory malformedData = bytes.concat(data, dirtyBits);
        (bool success, bytes memory returnData) = address(loadable).staticcall(malformedData);
        assertTrue(success, "extsload failed");
        assertEq(returnData.length % 0x20, 0, "return data length is not a multiple of 32");
        // assertEq(abi.decode(returnData, (bytes32[])), expected); //todo: uncomment once bumped forge-std lib
    }
}
