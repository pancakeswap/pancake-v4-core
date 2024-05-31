// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";

contract PoolIdLibraryTest is Test {
    using PoolIdLibrary for PoolKey;
    using CLPoolParametersHelper for bytes32;

    function test_toId() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(makeAddr("currency0")),
            currency1: Currency.wrap(makeAddr("currency1")),
            hooks: IHooks(makeAddr("hook")),
            // poolManager: IPoolManager(makeAddr("pm")),
            // fee: 100,
            parameters: bytes32(hex"1022").setFee(100).setPoolManagerId(1)
        });

        bytes32 id = PoolId.unwrap(key.toId());
        bytes32 abiEncodedId = keccak256(abi.encode(key));

        assertEq(id, abiEncodedId);
    }
}
