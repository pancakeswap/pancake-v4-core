// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Vault} from "../../src/Vault.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {ERC20PresetFixedSupply} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {FakePoolManagerRouter} from "./FakePoolManagerRouter.sol";
import {FakePoolManager} from "./FakePoolManager.sol";

import {IHooks} from "../../src/interfaces/IHooks.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";

/**
 * @notice Basic functionality test for Vault
 * More tests in terms of security and edge cases will be covered by VaultReentracy.t.sol & VaultInvariant.t.sol
 */
contract VaultTest is Test, NoIsolate, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    event AppRegistered(address indexed app);
    event LockAcquired();

    Vault public vault;
    IPoolManager public unRegPoolManager;
    FakePoolManager public fakePoolManager;
    FakePoolManager public fakePoolManager2;
    FakePoolManagerRouter public fakePoolManagerRouter;
    FakePoolManagerRouter public fakePoolManagerRouter2;

    Currency public currency0;
    Currency public currency1;

    PoolKey public poolKey;
    PoolKey public poolKey2;

    function setUp() public {
        vault = new Vault();

        unRegPoolManager = new FakePoolManager(vault);

        fakePoolManager = new FakePoolManager(vault);
        fakePoolManager2 = new FakePoolManager(vault);
        vault.registerApp(address(fakePoolManager));
        vault.registerApp(address(fakePoolManager2));

        currency0 = Currency.wrap(address(new ERC20PresetFixedSupply("C0", "C0", 100 ether, address(this))));
        currency1 = Currency.wrap(address(new ERC20PresetFixedSupply("C1", "C1", 100 ether, address(this))));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: fakePoolManager,
            fee: 0,
            parameters: 0x00
        });

        poolKey = key;
        fakePoolManagerRouter = new FakePoolManagerRouter(vault, key);

        PoolKey memory key2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: fakePoolManager2,
            fee: 1,
            parameters: 0x00
        });

        poolKey2 = key2;
        fakePoolManagerRouter2 = new FakePoolManagerRouter(vault, key2);
    }

    function test_bytecodeSize() public {
        snapSize("VaultBytecodeSize", address(vault));
    }

    function testRegisterPoolManager() public {
        assertEq(vault.isAppRegistered(address(unRegPoolManager)), false);
        assertEq(vault.isAppRegistered(address(fakePoolManager)), true);

        vm.expectEmit();
        emit AppRegistered(address(unRegPoolManager));
        snapStart("VaultTest#registerPoolManager");
        vault.registerApp(address(unRegPoolManager));
        snapEnd();

        assertEq(vault.isAppRegistered(address(unRegPoolManager)), true);
        assertEq(vault.isAppRegistered(address(fakePoolManager)), true);
    }

    function testAccountPoolBalanceDeltaFromUnregistedPoolManager() public {
        PoolKey memory key = PoolKey(currency0, currency1, IHooks(address(0)), unRegPoolManager, 0x0, 0x0);
        FakePoolManagerRouter unRegPoolManagerRouter = new FakePoolManagerRouter(vault, key);
        vm.expectRevert(IVault.AppUnregistered.selector);
        vm.prank(address(unRegPoolManagerRouter));
        vault.lock(hex"01");
    }

    function testAccountPoolBalanceDeltaFromArbitraryAddr() public {
        vm.expectRevert(IVault.AppUnregistered.selector);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"10");
    }

    function testAccountPoolBalanceDeltaWithoutLock() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: fakePoolManager,
            fee: uint24(3000),
            parameters: 0x00
        });
        BalanceDelta delta = toBalanceDelta(0x7, 0x8);

        vm.expectRevert(abi.encodeWithSelector(IVault.NoLocker.selector));
        vm.prank(address(fakePoolManager));
        vault.accountAppBalanceDelta(key, delta, address(this));
    }

    function testLockNotSettled() public {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"01");
    }

    function testLockNotSettled2() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);

        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
    }

    function testLockNotSettled3() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 8 ether);

        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
    }

    function testLockNotSettled4() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 12 ether);

        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
    }

    function testNotCorrectPoolManager() public {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vm.expectRevert();
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"06");
    }

    function testLockSettledWhenAddLiquidity() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        // Sync first, so reservesOfVault can be called
        vault.sync(currency0);
        vault.sync(currency1);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 0 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 0 ether);
        assertEq(vault.reservesOfVault(currency0), 0 ether);
        assertEq(vault.reservesOfVault(currency1), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 0 ether);

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 10 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 10 ether);
        assertEq(vault.reservesOfVault(currency0), 0 ether);
        assertEq(vault.reservesOfVault(currency1), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 0 ether);

        vm.prank(address(fakePoolManagerRouter));
        snapStart("VaultTest#lockSettledWhenAddLiquidity");
        vault.lock(hex"02");
        snapEnd();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 10 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 10 ether);
        assertEq(vault.reservesOfVault(currency0), 10 ether);
        assertEq(vault.reservesOfVault(currency1), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 10 ether);
    }

    function testLockSettledWhenSwap() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);

        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 10 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 10 ether);

        currency0.transfer(address(vault), 3 ether);
        vm.startPrank(address(fakePoolManagerRouter));
        snapStart("VaultTest#lockSettledWhenSwap");
        vault.lock(hex"03");
        snapEnd();
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 13 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 7 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 13 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 7 ether);

        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(fakePoolManagerRouter)), 3 ether);
    }

    function testLockWhenAlreadyLocked() public noIsolate {
        // deposit enough token in
        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"02");

        vm.expectRevert(abi.encodeWithSelector(IVault.LockerAlreadySet.selector, address(fakePoolManagerRouter)));

        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"07");
    }

    function testLockWhenMoreThanOnePoolManagers() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
        vm.stopPrank();

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter2));
        vault.lock(hex"02");
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

        currency0.transfer(address(vault), 3 ether);
        vm.prank(address(fakePoolManagerRouter));
        snapStart("VaultTest#lockSettledWhenMultiHopSwap");
        vault.lock(hex"03");
        snapEnd();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 23 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 17 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 13 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 7 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(fakePoolManagerRouter)), 3 ether);
    }

    function testVaultFuzz_mint(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"13");

        assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), amt);
    }

    function testVaultFuzz_mint_toSomeoneElse(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"14");

        assertEq(vault.balanceOf(Currency.unwrap(poolKey.currency1), currency0), amt);
    }

    function testVaultFuzz_burn(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"15");

        assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    }

    function testVaultFuzz_burnHalf(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"16");

        assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), amt - amt / 2);
    }

    function testVaultFuzz_burnFrom_withoutApprove(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        if (amt != 0) {
            vm.expectRevert();
        }

        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"20");
        vm.stopPrank();

        assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    }

    function testVaultFuzz_burnFrom_withApprove(uint256 amt) public noIsolate {
        amt = bound(amt, 0, 10 ether);
        // make sure router has enough tokens
        vault.sync(currency0);
        currency0.transfer(address(vault), amt);

        vm.startPrank(address(0x01));
        vault.approve(address(fakePoolManagerRouter), currency0, amt);
        vm.stopPrank();
        assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), amt);

        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"20");
        vm.stopPrank();

        assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
        assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), 0);

        // approve max
        {
            vault.sync(currency0);
            currency0.transfer(address(vault), amt);

            vm.startPrank(address(0x01));
            vault.approve(address(fakePoolManagerRouter), currency0, type(uint256).max);
            vm.stopPrank();

            vm.startPrank(address(fakePoolManagerRouter));
            vault.lock(hex"20");
            vm.stopPrank();

            assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
            assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), type(uint256).max);
        }

        // operator
        {
            vault.sync(currency0);
            currency0.transfer(address(vault), amt);

            // set a insufficient allowance
            vm.startPrank(address(0x01));
            vault.approve(address(fakePoolManagerRouter), currency0, 1);
            vm.stopPrank();

            vm.startPrank(address(0x01));
            vault.setOperator(address(fakePoolManagerRouter), true);
            vm.stopPrank();

            vm.startPrank(address(fakePoolManagerRouter));
            vault.lock(hex"20");
            vm.stopPrank();

            assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
            // transfer from operator don't consume allowance
            assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), 1);
        }
    }

    function testLockInSufficientBalanceWhenMoreThanOnePoolManagers() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        // ensure vault tload the currency in reserve first
        vault.sync(currency0);
        vault.sync(currency1);

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
        vm.stopPrank();

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter2));
        vault.lock(hex"02");
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
        assertEq(vault.reservesOfVault(currency0), 20 ether);
        assertEq(vault.reservesOfVault(currency1), 20 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

        assertEq(currency0.balanceOfSelf(), 80 ether);
        currency0.transfer(address(vault), 15 ether);

        vm.expectRevert(stdError.arithmeticError);
        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"04");
        vm.stopPrank();
    }

    function testLockFlashloanCrossMoreThanOnePoolManagers() public noIsolate {
        // router => vault.lock
        // vault.lock => periphery.lockAcquired
        // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

        // ensure vault tload the currency in reserve first
        vault.sync(currency0);
        vault.sync(currency1);

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter));
        vault.lock(hex"02");
        vm.stopPrank();

        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(fakePoolManagerRouter2));
        vault.lock(hex"02");
        vm.stopPrank();

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
        assertEq(vault.reservesOfVault(currency0), 20 ether);
        assertEq(vault.reservesOfVault(currency1), 20 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency1), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

        vm.startPrank(address(fakePoolManagerRouter));
        snapStart("VaultTest#lockSettledWhenFlashloan");
        vault.lock(hex"05");
        snapEnd();
        vm.stopPrank();
    }

    function test_CollectFee() public noIsolate {
        vault.sync(currency0);
        vault.sync(currency1);
        currency0.transfer(address(vault), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"02");

        // before collectFee assert
        assertEq(vault.reservesOfVault(currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 10 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(fakePoolManager)), 0 ether);

        // collectFee
        vm.prank(address(fakePoolManager));
        snapStart("VaultTest#collectFee");
        vault.collectFee(currency0, 10 ether, address(fakePoolManager));
        snapEnd();

        // after collectFee assert
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey.poolManager), currency0), 0 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(fakePoolManager)), 10 ether);
    }

    function test_CollectFeeFromRandomUser() public {
        currency0.transfer(address(vault), 10 ether);

        address bob = makeAddr("bob");
        vm.startPrank(bob);

        // expected revert as bob is not a valid pool manager
        vm.expectRevert(IVault.AppUnregistered.selector);
        vault.collectFee(currency0, 10 ether, bob);
    }

    function testTake_failsWithNoLiquidity() public {
        vm.expectRevert();
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"09");
    }

    function testLock_NoOpIsOk() public {
        vm.prank(address(fakePoolManagerRouter));
        snapStart("VaultTest#testLock_NoOp");
        vault.lock(hex"00");
        snapEnd();
    }

    function testLock_EmitsCorrectId() public {
        vm.expectEmit(false, false, false, true);
        emit LockAcquired();
        vm.prank(address(fakePoolManagerRouter));
        vault.lock(hex"00");
    }

    function testVault_ethSupport_transferInAndSettle() public noIsolate {
        FakePoolManagerRouter router = new FakePoolManagerRouter(
            vault,
            PoolKey({
                currency0: CurrencyLibrary.NATIVE,
                currency1: currency1,
                hooks: IHooks(address(0)),
                poolManager: fakePoolManager,
                fee: 0,
                parameters: 0x00
            })
        );

        // transfer in & settle
        {
            // ETH to router as router call .settle{value}
            // only way to settle NATIVE token is to call .settle{value}
            CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

            vault.sync(currency1);
            currency1.transfer(address(vault), 10 ether);

            vm.prank(address(router));
            vault.lock(hex"21");

            assertEq(CurrencyLibrary.NATIVE.balanceOf(address(vault)), 10 ether);
            assertEq(vault.reservesOfApp(address(fakePoolManager), CurrencyLibrary.NATIVE), 10 ether);
        }
    }

    function testVault_ethSupport_SettleNonNativeCurrencyWithValue() public {
        FakePoolManagerRouter router = new FakePoolManagerRouter(
            vault,
            PoolKey({
                currency0: currency1,
                currency1: CurrencyLibrary.NATIVE,
                hooks: IHooks(address(0)),
                poolManager: fakePoolManager,
                fee: 0,
                parameters: 0x00
            })
        );

        // transfer in & settle
        {
            // ETH to router as router call .settle{value}
            currency0.transfer(address(vault), 10 ether);
            CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

            vm.expectRevert(IVault.SettleNonNativeCurrencyWithValue.selector);
            vm.prank(address(router));
            vault.lock(hex"21"); // 0x02 assume both token are ERC20, so it call settle for ETH without value
        }
    }

    function testVault_ethSupport_settleAndTake() public noIsolate {
        FakePoolManagerRouter router = new FakePoolManagerRouter(
            vault,
            PoolKey({
                currency0: CurrencyLibrary.NATIVE,
                currency1: currency1,
                hooks: IHooks(address(0)),
                poolManager: fakePoolManager,
                fee: 0,
                parameters: 0x00
            })
        );

        CurrencyLibrary.NATIVE.transfer(address(router), 5 ether);

        // take and settle
        {
            vm.prank(address(router));
            vault.lock(hex"17");

            assertEq(CurrencyLibrary.NATIVE.balanceOf(address(vault)), 0);
            assertEq(vault.reservesOfApp(address(fakePoolManager), CurrencyLibrary.NATIVE), 0);
        }
    }

    function testVault_ethSupport_flashloan() public noIsolate {
        FakePoolManagerRouter router = new FakePoolManagerRouter(
            vault,
            PoolKey({
                currency0: CurrencyLibrary.NATIVE,
                currency1: currency1,
                hooks: IHooks(address(0)),
                poolManager: fakePoolManager,
                fee: 0,
                parameters: 0x00
            })
        );

        // make sure vault has enough tokens and ETH to router as router call .settle{value}
        CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

        vault.sync(currency1);
        currency1.transfer(address(vault), 10 ether);

        vm.startPrank(address(router));
        vault.lock(hex"21");
        vm.stopPrank();

        CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);
        currency1.transfer(address(vault), 10 ether);
        vm.startPrank(address(router));
        vault.lock(hex"21");
        vm.stopPrank();

        // take and settle
        {
            vm.startPrank(address(router));
            vault.lock(hex"22");
            vm.stopPrank();
        }
    }
}
