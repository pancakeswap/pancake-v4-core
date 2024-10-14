// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CLSlot0, CLSlot0Library} from "../../../src/pool-cl/types/CLSlot0.sol";

contract CLSlot0Test is Test {
    function test_slot0_constants_masks() public pure {
        assertEq(CLSlot0Library.MASK_160_BITS, type(uint160).max);
        assertEq(CLSlot0Library.MASK_24_BITS, type(uint24).max);
    }

    function test_fuzz_slot0_pack_unpack(uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
        public
        pure
    {
        // pack starting from "lowest" field
        CLSlot0 _slot0 = CLSlot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setProtocolFee(
            protocolFee
        ).setLpFee(lpFee);

        assertEq(_slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(_slot0.tick(), tick);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);

        // pack starting from "highest" field
        _slot0 = CLSlot0.wrap(bytes32(0)).setLpFee(lpFee).setProtocolFee(protocolFee).setTick(tick).setSqrtPriceX96(
            sqrtPriceX96
        );

        assertEq(_slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(_slot0.tick(), tick);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);
    }
}
