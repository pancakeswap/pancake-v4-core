// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/Test.sol";

import {PausableRole} from "../src/PausableRole.sol";
import {IPausableRole} from "../src/interfaces/IPausableRole.sol";

contract MockPausableRole is PausableRole {}

contract PausableRoleTest is Test, GasSnapshot {
    event PausableRoleGranted(address indexed account);
    event PausableRoleRevoked(address indexed account);

    MockPausableRole public mockPausableRole;
    address alice = makeAddr("alice");

    function setUp() public {
        mockPausableRole = new MockPausableRole();
    }

    function testGrantPausableRole_OnlyOwner() public {
        vm.expectEmit();
        emit PausableRoleGranted(alice);

        mockPausableRole.grantPausableRole(alice);
        assertEq(mockPausableRole.hasPausableRole(alice), true);
    }

    function testGrantPausableRole_NotOwner() public {
        vm.prank(alice);

        vm.expectRevert();
        mockPausableRole.grantPausableRole(alice);
    }

    function testRevokePausableRole() public {
        // pre-req: grant
        mockPausableRole.grantPausableRole(alice);
        assertEq(mockPausableRole.hasPausableRole(alice), true);

        vm.expectEmit();
        emit PausableRoleRevoked(alice);

        // revoke
        mockPausableRole.revokePausableRole(alice);
        assertEq(mockPausableRole.hasPausableRole(alice), false);
    }

    function testRevokePausableRole_NotOwner() public {
        vm.prank(alice);

        vm.expectRevert();
        mockPausableRole.revokePausableRole(alice);
    }

    function testPause_Owner() public {
        mockPausableRole.pause();
        assertEq(mockPausableRole.paused(), true);
    }

    function testPause_PausableRole() public {
        vm.expectRevert(IPausableRole.NoPausableRole.selector);
        vm.prank(alice);
        mockPausableRole.pause();

        // owner grant alice permission
        mockPausableRole.grantPausableRole(alice);

        // alice pause again
        vm.prank(alice);
        mockPausableRole.pause();
        assertEq(mockPausableRole.paused(), true);
    }

    function testUnpause_OnlyOwner() public {
        // pre-req: pause
        mockPausableRole.pause();
        assertEq(mockPausableRole.paused(), true);

        // unpause
        mockPausableRole.unpause();
        assertEq(mockPausableRole.paused(), false);
    }

    function testUnpause_NotOwner() public {
        // pre-req: pause
        mockPausableRole.pause();
        assertEq(mockPausableRole.paused(), true);

        // unpause
        vm.expectRevert();
        vm.prank(alice);
        mockPausableRole.unpause();
    }
}
