// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CLPoolParametersHelper} from "../../../src/pool-cl/libraries/CLPoolParametersHelper.sol";

contract CLPoolParametersHelperTest is Test {
    using CLPoolParametersHelper for bytes32;

    bytes32 params;

    function testFuzz_SetTickSpacing(int24 tickSpacing) external {
        bytes32 updatedParam = params.setTickSpacing(tickSpacing);
        assertEq(updatedParam.getTickSpacing(), tickSpacing);
    }
}
