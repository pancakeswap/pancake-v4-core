// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockProtocolFeeController} from "./helpers/ProtocolFeeControllers.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {CLPoolManagerOwner, ICLPoolManagerWithPauseOwnable} from "../../src/pool-cl/CLPoolManagerOwner.sol";
import {PoolManagerOwnable2Step} from "../../src/base/PoolManagerOwnable2Step.sol";
import {Pausable} from "../../src/base/Pausable.sol";
import {PausableRole} from "../../src/base/PausableRole.sol";

contract CLPoolManagerOwnerTest is Test, Deployers {
    IVault public vault;
    CLPoolManager public poolManager;
    MockProtocolFeeController public feeController;
    CLPoolManagerOwner clPoolManagerOwner;
    address alice = makeAddr("alice");

    function setUp() public {
        (vault, poolManager) = createFreshManager();
        feeController = new MockProtocolFeeController();
        clPoolManagerOwner = new CLPoolManagerOwner(ICLPoolManagerWithPauseOwnable(address(poolManager)));

        // transfer ownership and verify
        assertEq(poolManager.owner(), address(this));
        poolManager.transferOwnership(address(clPoolManagerOwner));
        assertEq(poolManager.owner(), address(clPoolManagerOwner));
    }

    function test_PausePoolManager_OnlyOwner() public {
        assertEq(poolManager.paused(), false);

        // pause and verify
        vm.expectEmit();
        emit Pausable.Paused(address(clPoolManagerOwner));
        clPoolManagerOwner.pausePoolManager();

        assertEq(poolManager.paused(), true);
    }

    function test_PausePoolManager_OnlyPausableRoleMember() public {
        // before: grant role
        assertEq(poolManager.paused(), false);
        clPoolManagerOwner.grantPausableRole(alice);

        // pause and verify
        vm.prank(alice);
        clPoolManagerOwner.pausePoolManager();
        assertEq(poolManager.paused(), true);
    }

    function test_PausePoolManager_NotOwnerOrPausableRoleMember() public {
        vm.expectRevert(PausableRole.NoPausableRole.selector);

        vm.prank(alice);
        clPoolManagerOwner.pausePoolManager();
    }

    function test_UnPausePoolManager_OnlyOwner() public {
        // before: pause
        clPoolManagerOwner.pausePoolManager();
        assertEq(poolManager.paused(), true);

        // unpause and verify
        vm.expectEmit();
        emit Pausable.Unpaused(address(clPoolManagerOwner));
        clPoolManagerOwner.unpausePoolManager();

        assertEq(poolManager.paused(), false);
    }

    function test_UnPausePoolManager_NotOwner() public {
        // before: pause
        clPoolManagerOwner.pausePoolManager();
        assertEq(poolManager.paused(), true);

        // as normal user
        vm.expectRevert();
        vm.prank(alice);
        clPoolManagerOwner.unpausePoolManager();

        // as role member
        clPoolManagerOwner.grantPausableRole(alice);
        vm.expectRevert();
        vm.prank(alice);
        clPoolManagerOwner.unpausePoolManager();
    }

    function test_SetProtocolFeeController_OnlyOwner() public {
        // before:
        assertEq(address(poolManager.protocolFeeController()), address(0));

        // after:
        clPoolManagerOwner.setProtocolFeeController(feeController);
        assertEq(address(poolManager.protocolFeeController()), address(feeController));
    }

    function test_SetProtocolFeeController_NotOwner() public {
        vm.expectRevert();

        vm.prank(alice);
        clPoolManagerOwner.setProtocolFeeController(feeController);
    }

    /// @dev in the real world, the new owner should be CLPoolManagerOwnerV2
    function test_TransferPoolManagerOwnership_OnlyOwner() public {
        // before:
        assertEq(poolManager.owner(), address(clPoolManagerOwner));

        // pending:
        // it's still the original owner if new owner not accept yet
        vm.expectEmit(true, true, true, true);
        emit PoolManagerOwnable2Step.PoolManagerOwnershipTransferStarted(address(clPoolManagerOwner), alice);
        clPoolManagerOwner.transferPoolManagerOwnership(alice);
        assertEq(poolManager.owner(), address(clPoolManagerOwner));
        assertEq(clPoolManagerOwner.pendingPoolManagerOwner(), alice);

        // after:
        vm.expectEmit(true, true, true, true);
        emit PoolManagerOwnable2Step.PoolManagerOwnershipTransferred(address(clPoolManagerOwner), alice);
        vm.prank(alice);
        clPoolManagerOwner.acceptPoolManagerOwnership();
        assertEq(poolManager.owner(), alice);
    }

    function test_TransferPoolManagerOwnership_NotOwner() public {
        vm.expectRevert();

        vm.prank(alice);
        clPoolManagerOwner.transferPoolManagerOwnership(alice);
    }

    function test_TransferPoolManagerOwnership_NotPendingPoolManagerOwner() public {
        clPoolManagerOwner.transferPoolManagerOwnership(alice);

        // if it's not from alice then revert
        vm.expectRevert(PoolManagerOwnable2Step.NotPendingPoolManagerOwner.selector);
        clPoolManagerOwner.acceptPoolManagerOwnership();
    }

    function test_TransferPoolManagerOwnership_OverridePendingOwner() public {
        // before:
        assertEq(poolManager.owner(), address(clPoolManagerOwner));

        // pending:
        // it's still the original owner if new owner not accept yet
        clPoolManagerOwner.transferPoolManagerOwnership(alice);
        assertEq(poolManager.owner(), address(clPoolManagerOwner));
        assertEq(clPoolManagerOwner.pendingPoolManagerOwner(), alice);

        // override pending owner
        clPoolManagerOwner.transferPoolManagerOwnership(makeAddr("bob"));
        assertEq(poolManager.owner(), address(clPoolManagerOwner));
        assertEq(clPoolManagerOwner.pendingPoolManagerOwner(), makeAddr("bob"));

        // alice no longer the valid pending owner
        vm.expectRevert(PoolManagerOwnable2Step.NotPendingPoolManagerOwner.selector);
        vm.prank(alice);
        clPoolManagerOwner.acceptPoolManagerOwnership();

        // bob is the new owner
        vm.prank(makeAddr("bob"));
        clPoolManagerOwner.acceptPoolManagerOwnership();
        assertEq(poolManager.owner(), makeAddr("bob"));
    }
}
