// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BinPoolParametersHelper} from "../../../src/pool-bin/libraries/BinPoolParametersHelper.sol";

contract BinPoolParametersHelperTest is Test {
    using BinPoolParametersHelper for bytes32;

    bytes32 params;

    function testFuzz_SetBinStep(uint16 binStep) external view {
        bytes32 updatedParam = params.setBinStep(binStep);
        assertEq(updatedParam.getBinStep(), binStep);
    }
}
