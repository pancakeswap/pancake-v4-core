// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Vault} from "../../src/Vault.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";
import {VaultReserves} from "../../src/libraries/VaultReserves.sol";
import {FakePoolManager} from "./FakePoolManager.sol";
import {FakePoolManagerRouter} from "./FakePoolManagerRouter.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";

contract VaultSyncTest is Test, TokenFixture, GasSnapshot, NoIsolate {
    using CurrencyLibrary for Currency;

    Vault public vault;
    FakePoolManager public fakePoolManager;
    FakePoolManagerRouter public router;

    function setUp() public {
        initializeTokens();

        vault = new Vault();
        fakePoolManager = new FakePoolManager(vault);
        vault.registerPoolManager(address(fakePoolManager));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: fakePoolManager,
            fee: 0,
            parameters: 0x00
        });

        router = new FakePoolManagerRouter(vault, key);
    }

    function test_sync_balanceIsZero() public noIsolate {
        assertEq(currency0.balanceOf(address(vault)), uint256(0));
        uint256 balance = vault.sync(currency0);

        assertEq(uint256(balance), 0);
        assertEq(vault.reservesOfVault(currency0), 0);
    }

    function test_sync_balanceIsNonZero() public noIsolate {
        // transfer without calling sync ahead cause token lost
        currency0.transfer(address(vault), 10 ether);

        uint256 currency0Balance = currency0.balanceOf(address(vault));
        assertGt(currency0Balance, uint256(0));

        // Without calling sync, getReserves should revert.
        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        vault.reservesOfVault(currency0);

        uint256 balance = vault.sync(currency0);
        assertEq(balance, currency0Balance, "balance not equal");
        assertEq(vault.reservesOfVault(currency0), balance);
    }

    function test_settle_withNoStartingBalance() public noIsolate {
        assertEq(currency0.balanceOf(address(vault)), uint256(0));

        // Sync has not been called.
        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        vault.reservesOfVault(currency0);

        vault.sync(currency0);
        currency0.transfer(address(vault), 10 ether);

        vm.prank(address(router));
        vault.lock(hex"13");

        assertEq(currency0.balanceOf(address(vault)), 10 ether);
        assertEq(vault.sync(currency0), 10 ether);
        assertEq(vault.reservesOfVault(currency0), 10 ether);
    }

    function test_settle_revertsIfSyncNotCalled() public noIsolate {
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);

        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        vm.prank(address(router));
        vault.lock(hex"02");
    }

    /// @notice When there is no balance and reserves are set to type(uint256).max, no delta should be applied.
    function test_settle_noBalanceInPool_shouldNotApplyDelta() public noIsolate {
        assertEq(currency0.balanceOf(address(vault)), uint256(0));

        // Sync has not been called.
        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        vault.reservesOfVault(currency0);

        vault.sync(currency0);
        assertEq(vault.reservesOfVault(currency0), 0);

        vm.prank(address(router));
        vault.lock(hex"18");
    }

    /// @notice When there is a balance, no delta should be applied.
    function test_settle_balanceInPool_shouldNotApplyDelta() public noIsolate {
        currency0.transfer(address(vault), 10 ether);

        uint256 currency0Balance = currency0.balanceOf(address(vault));

        // Sync has not been called.
        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        vault.reservesOfVault(currency0);

        vault.sync(currency0);
        assertEq(vault.reservesOfVault(currency0), currency0Balance);

        vm.prank(address(router));
        vault.lock(hex"18");
    }

    /// @notice When there is no actual balance in the pool, the ZERO_BALANCE stored in transient reserves should never actually used in calculating the amount paid in settle.
    /// This tests check that the reservesNow value is set to 0 not ZERO_BALANCE, by checking that an underflow happens when
    /// a) the contract balance is 0 and b) the reservesBefore value is out of date (sync isn't called again before settle).
    /// ie because paid = reservesNow - reservesBefore, and because reservesNow < reservesBefore an underflow should happen.
    function test_settle_afterTake_doesNotApplyDelta() public noIsolate {
        vault.sync(currency0);
        uint256 maxBalanceAmt = uint256(int256(type(int128).max));
        mint(maxBalanceAmt);
        currency0.transfer(address(vault), maxBalanceAmt);

        // Sync was called before transfer
        assertEq(vault.reservesOfVault(currency0), 0);

        vm.prank(address(router));
        vault.lock(hex"19");
    }

    // @notice This tests expected behavior if you DO NOT call sync. (ie. Do not interact with the pool manager properly. You can lose funds.)
    function test_settle_withoutSync_doesNotRevert_takesUserBalance() public noIsolate {
        currency0.transfer(address(vault), 10 ether);

        vault.sync(currency0);
        currency0.transfer(address(vault), 10 ether);

        // mint
        vm.prank(address(router));
        vault.lock(hex"23");

        assertEq(currency0.balanceOf(address(vault)), 20 ether);
        assertEq(vault.sync(currency0), 20 ether);
        assertEq(vault.reservesOfVault(currency0), 20 ether);
        assertEq(vault.balanceOf(address(router), currency0), 10 ether);
    }
}
