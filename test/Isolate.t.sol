// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/// @dev A test contract to ensure developers are using `--isolate` flag when running forge test
contract IsolateTest is Test {
    StorageLib storageLib;

    function setUp() public {
        storageLib = new StorageLib();
    }

    function testIsolateTest() public {
        // tstore key: 1 with value :2
        storageLib.tstore(1, 2);

        // toload key: 1
        uint256 val = storageLib.tload(1);

        // If the test is run with `--isolate` flag, the value should be 0
        // as --isolate run each top level call as seperate transaction, so tload will return 0
        assertEq(val, 0, "did you forget to use --isolate flag for 'forge test'?");
    }
}

contract StorageLib {
    function tstore(uint256 key, uint256 val) public {
        assembly {
            tstore(key, val)
        }
    }

    function tload(uint256 key) public view returns (uint256 val) {
        assembly {
            val := tload(key)
        }
        return val;
    }
}
