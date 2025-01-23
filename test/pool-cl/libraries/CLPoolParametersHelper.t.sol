// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CLPoolParametersHelper} from "../../../src/pool-cl/libraries/CLPoolParametersHelper.sol";

contract CLPoolParametersHelperTest is Test {
    function testGetTickSpacing() public pure {
        bytes32 paramsWithTickSpacing0 = bytes32(uint256(0x0));
        int24 tickSpacing0 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacing0);
        assertEq(tickSpacing0, 0);

        bytes32 paramsWithTickSpacingNegative13 = bytes32(uint256(0xfffff30000));
        int24 tickSpacingNegative13 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacingNegative13);
        assertEq(tickSpacingNegative13, -13);

        bytes32 paramsWithTickSpacing5 = bytes32(uint256(0x0000050000));
        int24 tickSpacinge5 = CLPoolParametersHelper.getTickSpacing(paramsWithTickSpacing5);
        assertEq(tickSpacinge5, 5);
    }
}
