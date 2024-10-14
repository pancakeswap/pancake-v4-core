// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BinSlot0, BinSlot0Library} from "../../../src/pool-bin/types/BinSlot0.sol";

contract BinSlot0Test is Test {
    function test_slot0_constants_masks() public pure {
        assertEq(BinSlot0Library.MASK_24_BITS, type(uint24).max);
    }

    function test_fuzz_slot0_pack_unpack(uint24 activeId, uint24 protocolFee, uint24 lpFee) public pure {
        // pack starting from "lowest" field
        BinSlot0 _slot0 = BinSlot0.wrap(bytes32(0)).setActiveId(activeId).setProtocolFee(protocolFee).setLpFee(lpFee);

        assertEq(_slot0.activeId(), activeId);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);

        // pack starting from "highest" field
        _slot0 = BinSlot0.wrap(bytes32(0)).setLpFee(lpFee).setProtocolFee(protocolFee).setActiveId(activeId);

        assertEq(_slot0.activeId(), activeId);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);
    }
}
