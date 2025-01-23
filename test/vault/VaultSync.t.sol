// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IVault, Vault} from "../../src/Vault.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";
import {VaultReserve} from "../../src/libraries/VaultReserve.sol";
import {FakePoolManager} from "./FakePoolManager.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {NativeERC20} from "../helpers/NativeERC20.sol";

contract VaultSyncTest is Test, TokenFixture, NoIsolate {
    Vault public vault;
    FakePoolManager public fakePoolManager;
    PoolKey public poolKey;

    function setUp() public {
        initializeTokens();

        vault = new Vault();
        fakePoolManager = new FakePoolManager(vault);
        vault.registerApp(address(fakePoolManager));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: fakePoolManager,
            fee: 0,
            parameters: 0x00
        });
    }

    function test_sync_balanceIsZero() public {
        vault.lock(abi.encodeCall(VaultSyncTest._test_sync_balanceIsZero, ()));
    }

    function _test_sync_balanceIsZero() external {
        assertEq(currency0.balanceOf(address(vault)), uint256(0));
        vault.sync(currency0);

        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 0);
    }

    function test_sync_balanceIsNonZero() public {
        vault.lock(abi.encodeCall(VaultSyncTest._test_sync_balanceIsNonZero, ()));
    }

    function _test_sync_balanceIsNonZero() external {
        // transfer without calling sync ahead cause token lost
        currency0.transfer(address(vault), 10 ether);
        uint256 currency0Balance = currency0.balanceOf(address(vault));
        assertEq(currency0Balance, 10 ether);

        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, currency0Balance, "balance not equal");
    }

    function test_settle_startWithZeroBalance() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_startWithZeroBalance, ()));
    }

    function _test_settle_startWithZeroBalance() external {
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        // it should currently wait for the next settle
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 0);

        currency0.transfer(address(vault), 10 ether);
        vault.settle();

        // make sure it's cleared after settle
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);

        // mint 10 ether currency0
        vault.mint(address(this), poolKey.currency0, 10 ether);
        assertEq(currency0.balanceOf(address(vault)), 10 ether);

        vault.sync(currency0);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 10 ether);
    }

    function test_settleFor_startWithZeroBalance() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_startWithZeroBalance, ()));
    }

    function _test_settleFor_startWithZeroBalance() external {
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        // it should currently wait for the next settle
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 0);

        currency0.transfer(address(vault), 10 ether);
        vault.settleFor(address(this));

        // make sure it's cleared after settle
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);

        // mint 10 ether currency0
        vault.mint(address(this), poolKey.currency0, 10 ether);
        assertEq(currency0.balanceOf(address(vault)), 10 ether);

        vault.sync(currency0);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 10 ether);
    }

    function test_sync() public {
        // it's ok to sync without lock
        vault.sync(currency0);
    }

    function test_sync_twiceWithoutSettle() public {
        vault.lock(abi.encodeCall(VaultSyncTest._test_sync_twiceWithoutSettle, ()));
    }

    function _test_sync_twiceWithoutSettle() external {
        /// @dev don't do this in production, it will cause the token forever locked in the vault
        currency0.transfer(address(vault), 5 ether);
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 5 ether);

        /// @dev don't do this in production, it will cause the token forever locked in the vault
        currency1.transfer(address(vault), 10 ether);
        vault.sync(currency1);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency1));
        assertEq(amount, 10 ether);
    }

    function test_sync_twiceWithSettle() public {
        vault.lock(abi.encodeCall(VaultSyncTest._test_sync_twiceWithSettle, ()));
    }

    function _test_sync_twiceWithSettle() external {
        /// @dev don't do this in production, it will cause the token forever locked in the vault
        currency0.transfer(address(vault), 5 ether);
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 5 ether);

        /// @dev correct usage: sync - transfer - settle
        vault.sync(currency1);
        currency1.transfer(address(vault), 10 ether);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency1));
        assertEq(amount, 0 ether);

        vault.settle();
        vault.sync(currency1);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency1));
        assertEq(amount, 10 ether);

        vault.take(currency1, address(this), 10 ether);
    }

    function test_sync_twiceWithSettleNative() public {
        vault.lock(abi.encodeCall(VaultSyncTest._test_sync_twiceWithSettleNative, ()));
    }

    function _test_sync_twiceWithSettleNative() external {
        /// @dev don't do this in production, it will cause the token forever locked in the vault
        currency0.transfer(address(vault), 5 ether);
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 5 ether);

        /// @dev correct usage: sync - transfer - settle
        vault.sync(CurrencyLibrary.NATIVE);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(CurrencyLibrary.NATIVE));
        assertEq(amount, 0 ether);

        vault.settle{value: 1 ether}();
        vault.take(CurrencyLibrary.NATIVE, makeAddr("receiver"), 1 ether);
    }

    function test_settle_nativeTokenWithoutFund() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_nativeTokenWithoutFund, ()));
    }

    function _test_settle_nativeTokenWithoutFund() external {
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);
        vault.settle();
        // nothing should happen
        int256 deltaAfter = vault.currencyDelta(address(this), CurrencyLibrary.NATIVE);
        assertEq(deltaAfter, 0);
    }

    function test_settleFor_nativeTokenWithoutFund() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_nativeTokenWithoutFund, ()));
    }

    function _test_settleFor_nativeTokenWithoutFund() external {
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);
        vault.settleFor(address(this));
        // nothing should happen
        int256 deltaAfter = vault.currencyDelta(address(this), CurrencyLibrary.NATIVE);
        assertEq(deltaAfter, 0);
    }

    function test_settle_nativeTokenWithFund() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_nativeTokenWithFund, ()));
    }

    function _test_settle_nativeTokenWithFund() external {
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);
        vault.settle{value: 1 ether}();
        int256 deltaAfter = vault.currencyDelta(address(this), CurrencyLibrary.NATIVE);
        assertEq(deltaAfter, 1 ether);

        // balance the delta
        vault.take(CurrencyLibrary.NATIVE, makeAddr("receiver"), 1 ether);
    }

    function test_settleFor_nativeTokenWithFund() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_nativeTokenWithFund, ()));
    }

    function _test_settleFor_nativeTokenWithFund() external {
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), address(0));
        assertEq(amount, 0);
        vault.settleFor{value: 1 ether}(address(this));
        int256 deltaAfter = vault.currencyDelta(address(this), CurrencyLibrary.NATIVE);
        assertEq(deltaAfter, 1 ether);

        // balance the delta
        vault.take(CurrencyLibrary.NATIVE, makeAddr("receiver"), 1 ether);
    }

    function test_settle_ERC20TokenWithValue() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_ERC20TokenWithValue, ()));
    }

    function _test_settle_ERC20TokenWithValue() external {
        vault.sync(currency0);
        vm.expectRevert(abi.encodeWithSelector(IVault.SettleNonNativeCurrencyWithValue.selector));
        vault.settle{value: 1 ether}();
    }

    function test_settleFor_ERC20TokenWithValue() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_ERC20TokenWithValue, ()));
    }

    function _test_settleFor_ERC20TokenWithValue() external {
        vault.sync(currency0);
        vm.expectRevert(abi.encodeWithSelector(IVault.SettleNonNativeCurrencyWithValue.selector));
        vault.settleFor{value: 1 ether}(address(this));
    }

    // @notice This tests expected behavior if you DO NOT call sync. (ie. Do not interact with the pool manager properly. You can lose funds.)
    function test_settle_transferBeforeSync() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_transferBeforeSync, ()));
    }

    function _test_settle_transferBeforeSync() external {
        // the fund is lost and is locked in the vault
        currency0.transfer(address(vault), 10 ether);
        vault.sync(currency0);
        currency0.transfer(address(vault), 10 ether);

        vault.settle();
        assertEq(vault.currencyDelta(address(this), currency0), 10 ether);
        vault.mint(address(this), poolKey.currency0, 10 ether);

        // 20 ether in vault but only 10 belongs to user
        assertEq(currency0.balanceOf(address(vault)), 20 ether);
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 20 ether);
        assertEq(vault.balanceOf(address(this), currency0), 10 ether);
    }

    function test_settleFor_transferBeforeSync() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_transferBeforeSync, ()));
    }

    function _test_settleFor_transferBeforeSync() external {
        // the fund is lost and is locked in the vault
        currency0.transfer(address(vault), 10 ether);
        vault.sync(currency0);
        currency0.transfer(address(vault), 10 ether);

        vault.settleFor(address(this));
        assertEq(vault.currencyDelta(address(this), currency0), 10 ether);
        vault.mint(address(this), poolKey.currency0, 10 ether);

        // 20 ether in vault but only 10 belongs to user
        assertEq(currency0.balanceOf(address(vault)), 20 ether);
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 20 ether);
        assertEq(vault.balanceOf(address(this), currency0), 10 ether);
    }

    function test_settle_NativeERC20() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settle_NativeERC20, ()));
    }

    function _test_settle_NativeERC20() external {
        Currency currency = Currency.wrap(address(new NativeERC20()));
        vault.sync(currency);

        // mixing those two are not allowed
        vm.expectRevert(IVault.SettleNonNativeCurrencyWithValue.selector);
        vault.settle{value: 1 ether}();

        // erc20 way of settling
        currency.transfer(address(vault), 1 ether);
        vault.settle();

        // native way of settling
        vault.settle{value: 1 ether}();

        // from vault perspective they are two different currencies
        vault.mint(address(this), currency, 1 ether);
        vault.mint(address(this), CurrencyLibrary.NATIVE, 1 ether);

        assertEq(address(vault).balance, 2 ether);
        assertEq(currency.balanceOf(address(vault)), 2 ether);
    }

    function test_settleFor_NativeERC20() public noIsolate {
        vault.lock(abi.encodeCall(VaultSyncTest._test_settleFor_NativeERC20, ()));
    }

    function _test_settleFor_NativeERC20() external {
        Currency currency = Currency.wrap(address(new NativeERC20()));
        vault.sync(currency);

        // mixing those two are not allowed
        vm.expectRevert(IVault.SettleNonNativeCurrencyWithValue.selector);
        vault.settleFor{value: 1 ether}(address(this));

        // erc20 way of settling
        currency.transfer(address(vault), 1 ether);
        vault.settleFor(address(this));

        // native way of settling
        vault.settleFor{value: 1 ether}(address(this));

        // from vault perspective they are two different currencies
        vault.mint(address(this), currency, 1 ether);
        vault.mint(address(this), CurrencyLibrary.NATIVE, 1 ether);

        assertEq(address(vault).balance, 2 ether);
        assertEq(currency.balanceOf(address(vault)), 2 ether);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory result) {
        // forward the call and bubble up the error if revert
        bool success;
        (success, result) = address(this).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }
}
