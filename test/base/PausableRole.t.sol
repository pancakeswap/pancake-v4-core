// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PausableRole} from "../../src/base/PausableRole.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract PausableRoleImplemetation is PausableRole {}

contract PausableRoleTest is Test {
    PausableRoleImplemetation public pausableRole;
    address alice = makeAddr("alice");

    function setUp() public {
        pausableRole = new PausableRoleImplemetation();
        assertEq(pausableRole.owner(), address(this));
    }

    function test_GrantPausableRole_OnlyOwner() public {
        // before
        assertFalse(pausableRole.hasPausableRole(alice));

        // grant and verify
        vm.expectEmit();
        emit PausableRole.PausableRoleGranted(alice);
        pausableRole.grantPausableRole(alice);

        assertTrue(pausableRole.hasPausableRole(alice));
    }

    function test_GrantPausableRole_NotOwner() public {
        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        pausableRole.grantPausableRole(alice);
    }

    function test_RevokePausableRole_OnlyOwner() public {
        // before
        pausableRole.grantPausableRole(alice);
        assertTrue(pausableRole.hasPausableRole(alice));

        // revoke and verify
        vm.expectEmit();
        emit PausableRole.PausableRoleRevoked(alice);
        pausableRole.revokePausableRole(alice);
        assertFalse(pausableRole.hasPausableRole(alice));
    }

    function test_RevokePausableRole_NotOwner() public {
        vm.prank(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        pausableRole.revokePausableRole(alice);
    }
}
