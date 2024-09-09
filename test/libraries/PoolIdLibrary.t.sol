// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

contract PoolIdLibraryTest is Test {
    function test_toId() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(makeAddr("currency0")),
            currency1: Currency.wrap(makeAddr("currency1")),
            hooks: IHooks(makeAddr("hook")),
            poolManager: IPoolManager(makeAddr("pm")),
            fee: 100,
            parameters: hex"1022"
        });

        bytes32 id = PoolId.unwrap(key.toId());
        bytes32 abiEncodedId = keccak256(abi.encode(key));

        assertEq(id, abiEncodedId);
    }
}
