// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {CLPoolParametersHelper} from "../../../src/pool-cl/libraries/CLPoolParametersHelper.sol";

contract CLPoolParametersHelperTest is Test, GasSnapshot {
    function testGetTickSpacing() public {
        bytes32 paramsWithTickSpacing0 = bytes32(uint256(0x0));
        int24 tickSpacing0 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacing0);
        assertEq(tickSpacing0, 0);

        bytes32 paramsWithTickSpacing13 = bytes32(uint256(0xd0000));
        int24 tickSpacing13 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacing13);
        assertEq(tickSpacing13, 13);

        bytes32 paramsWithTickSpacing5 = bytes32(uint256(0x0000050000));
        int24 tickSpacinge5 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacing5);
        assertEq(tickSpacinge5, 5);
    }
}
