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
import {FakePoolManager} from "./FakePoolManager.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";
import {CurrencySettlement} from "../helpers/CurrencySettlement.sol";

/**
 * @notice Basic functionality test for Vault
 * More tests in terms of security and edge cases will be covered by VaultReentracy.t.sol & VaultInvariant.t.sol
 */
contract VaultTest is Test, NoIsolate, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencySettlement for Currency;

    error ContractSizeTooLarge(uint256 diff);

    Vault public vault;
    FakePoolManager public unRegPoolManager;
    FakePoolManager public poolManager1;
    FakePoolManager public poolManager2;

    Currency public currency0;
    Currency public currency1;

    PoolKey public poolKey1;
    PoolKey public poolKey2;

    function setUp() public {
        vault = new Vault();

        unRegPoolManager = new FakePoolManager(vault);

        poolManager1 = new FakePoolManager(vault);
        poolManager2 = new FakePoolManager(vault);
        vault.registerApp(address(poolManager1));
        vault.registerApp(address(poolManager2));

        currency0 = Currency.wrap(address(new ERC20PresetFixedSupply("C0", "C0", 100 ether, address(this))));
        currency1 = Currency.wrap(address(new ERC20PresetFixedSupply("C1", "C1", 100 ether, address(this))));

        poolKey1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager1,
            fee: 0,
            parameters: 0x00
        });

        poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager2,
            fee: 1,
            parameters: 0x00
        });
    }

    function test_bytecodeSize() public {
        snapSize("VaultBytecodeSize", address(vault));
        if (address(vault).code.length > 24576) {
            revert ContractSizeTooLarge(address(vault).code.length - 24576);
        }
    }

    function testRegisterPoolManager() public {
        assertEq(vault.isAppRegistered(address(unRegPoolManager)), false);
        assertEq(vault.isAppRegistered(address(poolManager1)), true);

        vm.expectEmit();
        emit IVault.AppRegistered(address(unRegPoolManager));
        snapStart("VaultTest#registerPoolManager");
        vault.registerApp(address(unRegPoolManager));
        snapEnd();

        assertEq(vault.isAppRegistered(address(unRegPoolManager)), true);
        assertEq(vault.isAppRegistered(address(poolManager1)), true);
    }

    function testAccountPoolBalanceDeltaFromUnregistedPoolManager() public {
        vault.lock(abi.encodeCall(VaultTest._testAccountPoolBalanceDeltaFromUnregistedPoolManager, ()));
    }

    function _testAccountPoolBalanceDeltaFromUnregistedPoolManager() external {
        PoolKey memory key = PoolKey(currency0, currency1, IHooks(address(0)), unRegPoolManager, 0x0, 0x0);
        vm.expectRevert(IVault.AppUnregistered.selector);
        unRegPoolManager.mockAccounting(key, -10 ether, -10 ether);
    }

    function testAccountPoolBalanceDeltaFromArbitraryAddr() public {
        vault.lock(abi.encodeCall(VaultTest._testAccountPoolBalanceDeltaFromArbitraryAddr, ()));
    }

    function _testAccountPoolBalanceDeltaFromArbitraryAddr() external {
        vm.expectRevert(IVault.AppUnregistered.selector);
        vault.accountAppBalanceDelta(poolKey1, toBalanceDelta(int128(-1), int128(0)), address(0));
    }

    function testAccountPoolBalanceDeltaWithoutLock() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager1,
            fee: uint24(3000),
            parameters: 0x00
        });
        BalanceDelta delta = toBalanceDelta(0x7, 0x8);

        vm.expectRevert(abi.encodeWithSelector(IVault.NoLocker.selector));
        vm.prank(address(poolManager1));
        vault.accountAppBalanceDelta(key, delta, address(this));
    }

    function testLockNotSettledWithoutPayment() public {
        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vault.lock(abi.encodeCall(VaultTest._testLockNotSettledWithoutPayment, ()));
    }

    function _testLockNotSettledWithoutPayment() external {
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);
    }

    function testLockNotSettledWithoutFullyPayment() public noIsolate {
        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vault.lock(abi.encodeCall(VaultTest._testLockNotSettledWithoutFullyPayment, ()));
    }

    function _testLockNotSettledWithoutFullyPayment() external {
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);

        currency0.settle(vault, address(this), 10 ether, false);

        // didnt actually transfer the currency
        vault.sync(currency1);
        vault.settle();
    }

    function testLockNotSettledAsPayTooMuch() public noIsolate {
        vm.expectRevert(IVault.CurrencyNotSettled.selector);
        vault.lock(abi.encodeCall(VaultTest._testLockNotSettledAsPayTooMuch, ()));
    }

    function _testLockNotSettledAsPayTooMuch() external {
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);
        currency0.settle(vault, address(this), 10 ether, false);
        currency1.settle(vault, address(this), 12 ether, false);
    }

    function testNotCorrectPoolManager() public {
        // DOUBLE-CHECK:
        // The tx will complete without revert, is this going to be a problem ?
        vault.lock(abi.encodeCall(VaultTest._testNotCorrectPoolManager, ()));
    }

    function _testNotCorrectPoolManager() external {
        // poolKey.poolManager was hacked hence not equal to msg.sender
        PoolKey memory maliciousPoolKey = poolKey1;
        poolManager1.mockAccounting(maliciousPoolKey, -3 ether, -3 ether);
        currency0.settle(vault, address(this), 3 ether, false);
        currency1.settle(vault, address(this), 3 ether, false);

        maliciousPoolKey.poolManager = IPoolManager(address(0));
        poolManager1.mockAccounting(maliciousPoolKey, -3 ether, 3 ether);
        currency0.settle(vault, address(this), 3 ether, false);
        currency1.take(vault, address(this), 3 ether, false);
    }

    function testLockSettledWhenAddLiquidity() public noIsolate {
        vault.lock(abi.encodeCall(VaultTest._testLockSettledWhenAddLiquidity, ()));
    }

    function _testLockSettledWhenAddLiquidity() external {
        // verify it's all zero before adding liquidity
        vault.sync(currency0);
        (Currency currency, uint256 amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency0));
        assertEq(amount, 0 ether);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 0 ether);
        currency0.transfer(address(vault), 10 ether);
        vault.settle();

        vault.sync(currency1);
        (currency, amount) = vault.getVaultReserve();
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency1));
        assertEq(amount, 0 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 0 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 0 ether);

        currency1.transfer(address(vault), 10 ether);
        vault.settle();

        // generating delta for adding liquidity
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 10 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 10 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 10 ether);
    }

    function testLockSettledWhenSwap() public noIsolate {
        vault.lock(abi.encodeCall(VaultTest._testLockSettledWhenSwap, ()));
    }

    function _testLockSettledWhenSwap() external {
        // adding enough liquidity before swap
        currency0.settle(vault, address(this), 10 ether, false);
        currency1.settle(vault, address(this), 10 ether, false);
        poolManager1.mockAccounting(poolKey1, -10 ether, -10 ether);

        uint256 token0Before = currency0.balanceOfSelf();
        uint256 token1Before = currency1.balanceOfSelf();

        // swap
        poolManager1.mockAccounting(poolKey1, -3 ether, 3 ether);
        currency0.settle(vault, address(this), 3 ether, false);
        currency1.take(vault, address(this), 3 ether, false);

        // user paid 3 token0 and received 3 token1
        assertEq(token0Before - currency0.balanceOfSelf(), 3 ether);
        assertEq(currency1.balanceOfSelf() - token1Before, 3 ether);

        // vault received 3 token0 and paid 3 token1
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 13 ether);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 7 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 13 ether);
        assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 7 ether);
    }

    function testLockWhenAlreadyLocked() public noIsolate {
        vm.expectRevert(abi.encodeWithSelector(IVault.LockerAlreadySet.selector, address(this)));
        vault.lock(abi.encodeCall(VaultTest._testLockWhenAlreadyLocked, ()));
    }

    function _testLockWhenAlreadyLocked() external {
        vault.lock(new bytes(0));
    }

    // function testLockWhenMoreThanOnePoolManagers() public noIsolate {
    //     // router => vault.lock
    //     // vault.lock => periphery.lockAcquired
    //     // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

    //     vault.sync(currency0);
    //     vault.sync(currency1);
    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter2));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
    //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

    //     currency0.transfer(address(vault), 3 ether);
    //     vm.prank(address(fakePoolManagerRouter));
    //     snapStart("VaultTest#lockSettledWhenMultiHopSwap");
    //     vault.lock(hex"03");
    //     snapEnd();

    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 23 ether);
    //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 17 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 13 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 7 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

    //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(fakePoolManagerRouter)), 3 ether);
    // }

    // function testVaultFuzz_mint(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"13");

    //     assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), amt);
    // }

    // function testVaultFuzz_mint_toSomeoneElse(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"14");

    //     assertEq(vault.balanceOf(Currency.unwrap(poolKey1.currency1), currency0), amt);
    // }

    // function testVaultFuzz_burn(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"15");

    //     assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    // }

    // function testVaultFuzz_burnHalf(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"16");

    //     assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), amt - amt / 2);
    // }

    // function testVaultFuzz_burnFrom_withoutApprove(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     if (amt != 0) {
    //         vm.expectRevert();
    //     }

    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"20");
    //     vm.stopPrank();

    //     assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    // }

    // function testVaultFuzz_burnFrom_withApprove(uint256 amt) public noIsolate {
    //     amt = bound(amt, 0, 10 ether);
    //     // make sure router has enough tokens
    //     vault.sync(currency0);
    //     currency0.transfer(address(vault), amt);

    //     vm.startPrank(address(0x01));
    //     vault.approve(address(fakePoolManagerRouter), currency0, amt);
    //     vm.stopPrank();
    //     assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), amt);

    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"20");
    //     vm.stopPrank();

    //     assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    //     assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), 0);

    //     // approve max
    //     {
    //         vault.sync(currency0);
    //         currency0.transfer(address(vault), amt);

    //         vm.startPrank(address(0x01));
    //         vault.approve(address(fakePoolManagerRouter), currency0, type(uint256).max);
    //         vm.stopPrank();

    //         vm.startPrank(address(fakePoolManagerRouter));
    //         vault.lock(hex"20");
    //         vm.stopPrank();

    //         assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    //         assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), type(uint256).max);
    //     }

    //     // operator
    //     {
    //         vault.sync(currency0);
    //         currency0.transfer(address(vault), amt);

    //         // set a insufficient allowance
    //         vm.startPrank(address(0x01));
    //         vault.approve(address(fakePoolManagerRouter), currency0, 1);
    //         vm.stopPrank();

    //         vm.startPrank(address(0x01));
    //         vault.setOperator(address(fakePoolManagerRouter), true);
    //         vm.stopPrank();

    //         vm.startPrank(address(fakePoolManagerRouter));
    //         vault.lock(hex"20");
    //         vm.stopPrank();

    //         assertEq(vault.balanceOf(address(fakePoolManagerRouter), currency0), 0);
    //         // transfer from operator don't consume allowance
    //         assertEq(vault.allowance(address(0x01), address(fakePoolManagerRouter), currency0), 1);
    //     }
    // }

    // function testLockInSufficientBalanceWhenMoreThanOnePoolManagers() public noIsolate {
    //     // router => vault.lock
    //     // vault.lock => periphery.lockAcquired
    //     // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

    //     // ensure vault tload the currency in reserve first
    //     vault.sync(currency0);
    //     vault.sync(currency1);

    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter2));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
    //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
    //     assertEq(vault.reservesOfVault(currency0), 20 ether);
    //     assertEq(vault.reservesOfVault(currency1), 20 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

    //     assertEq(currency0.balanceOfSelf(), 80 ether);
    //     currency0.transfer(address(vault), 15 ether);

    //     vm.expectRevert(stdError.arithmeticError);
    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"04");
    //     vm.stopPrank();
    // }

    // function testLockFlashloanCrossMoreThanOnePoolManagers() public noIsolate {
    //     // router => vault.lock
    //     // vault.lock => periphery.lockAcquired
    //     // periphery.lockAcquired => FakePoolManager.XXX => vault.accountAppBalanceDelta

    //     // ensure vault tload the currency in reserve first
    //     vault.sync(currency0);
    //     vault.sync(currency1);

    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(fakePoolManagerRouter2));
    //     vault.lock(hex"02");
    //     vm.stopPrank();

    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 20 ether);
    //     assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 20 ether);
    //     assertEq(vault.reservesOfVault(currency0), 20 ether);
    //     assertEq(vault.reservesOfVault(currency1), 20 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency1), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey2.poolManager), currency1), 10 ether);

    //     vm.startPrank(address(fakePoolManagerRouter));
    //     snapStart("VaultTest#lockSettledWhenFlashloan");
    //     vault.lock(hex"05");
    //     snapEnd();
    //     vm.stopPrank();
    // }

    // function test_CollectFee() public noIsolate {
    //     vault.sync(currency0);
    //     vault.sync(currency1);
    //     currency0.transfer(address(vault), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"02");

    //     // before collectFee assert
    //     assertEq(vault.reservesOfVault(currency0), 10 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 10 ether);
    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(poolManagerA)), 0 ether);

    //     // collectFee
    //     vm.prank(address(poolManagerA));
    //     snapStart("VaultTest#collectFee");
    //     vault.collectFee(currency0, 10 ether, address(poolManagerA));
    //     snapEnd();

    //     // after collectFee assert
    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 0 ether);
    //     assertEq(vault.reservesOfApp(address(poolKey1.poolManager), currency0), 0 ether);
    //     assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(poolManagerA)), 10 ether);
    // }

    // function test_CollectFeeFromRandomUser() public {
    //     currency0.transfer(address(vault), 10 ether);

    //     address bob = makeAddr("bob");
    //     vm.startPrank(bob);

    //     // expected revert as bob is not a valid pool manager
    //     vm.expectRevert(IVault.AppUnregistered.selector);
    //     vault.collectFee(currency0, 10 ether, bob);
    // }

    // function testTake_failsWithNoLiquidity() public {
    //     vm.expectRevert();
    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"09");
    // }

    // function testLock_NoOpIsOk() public {
    //     vm.prank(address(fakePoolManagerRouter));
    //     snapStart("VaultTest#testLock_NoOp");
    //     vault.lock(hex"00");
    //     snapEnd();
    // }

    // function testLock_EmitsCorrectId() public {
    //     vm.expectEmit(false, false, false, true);
    //     emit LockAcquired();
    //     vm.prank(address(fakePoolManagerRouter));
    //     vault.lock(hex"00");
    // }

    // function testVault_ethSupport_transferInAndSettle() public noIsolate {
    //     FakePoolManagerRouter router = new FakePoolManagerRouter(
    //         vault,
    //         PoolKey({
    //             currency0: CurrencyLibrary.NATIVE,
    //             currency1: currency1,
    //             hooks: IHooks(address(0)),
    //             poolManager: poolManagerA,
    //             fee: 0,
    //             parameters: 0x00
    //         })
    //     );

    //     // transfer in & settle
    //     {
    //         // ETH to router as router call .settle{value}
    //         // only way to settle NATIVE token is to call .settle{value}
    //         CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

    //         vault.sync(currency1);
    //         currency1.transfer(address(vault), 10 ether);

    //         vm.prank(address(router));
    //         vault.lock(hex"21");

    //         assertEq(CurrencyLibrary.NATIVE.balanceOf(address(vault)), 10 ether);
    //         assertEq(vault.reservesOfApp(address(poolManagerA), CurrencyLibrary.NATIVE), 10 ether);
    //     }
    // }

    // function testVault_ethSupport_SettleNonNativeCurrencyWithValue() public {
    //     FakePoolManagerRouter router = new FakePoolManagerRouter(
    //         vault,
    //         PoolKey({
    //             currency0: currency1,
    //             currency1: CurrencyLibrary.NATIVE,
    //             hooks: IHooks(address(0)),
    //             poolManager: poolManagerA,
    //             fee: 0,
    //             parameters: 0x00
    //         })
    //     );

    //     // transfer in & settle
    //     {
    //         // ETH to router as router call .settle{value}
    //         currency0.transfer(address(vault), 10 ether);
    //         CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

    //         vm.expectRevert(IVault.SettleNonNativeCurrencyWithValue.selector);
    //         vm.prank(address(router));
    //         vault.lock(hex"21"); // 0x02 assume both token are ERC20, so it call settle for ETH without value
    //     }
    // }

    // function testVault_ethSupport_settleAndTake() public noIsolate {
    //     FakePoolManagerRouter router = new FakePoolManagerRouter(
    //         vault,
    //         PoolKey({
    //             currency0: CurrencyLibrary.NATIVE,
    //             currency1: currency1,
    //             hooks: IHooks(address(0)),
    //             poolManager: poolManagerA,
    //             fee: 0,
    //             parameters: 0x00
    //         })
    //     );

    //     CurrencyLibrary.NATIVE.transfer(address(router), 5 ether);

    //     // take and settle
    //     {
    //         vm.prank(address(router));
    //         vault.lock(hex"17");

    //         assertEq(CurrencyLibrary.NATIVE.balanceOf(address(vault)), 0);
    //         assertEq(vault.reservesOfApp(address(poolManagerA), CurrencyLibrary.NATIVE), 0);
    //     }
    // }

    // function testVault_ethSupport_flashloan() public noIsolate {
    //     FakePoolManagerRouter router = new FakePoolManagerRouter(
    //         vault,
    //         PoolKey({
    //             currency0: CurrencyLibrary.NATIVE,
    //             currency1: currency1,
    //             hooks: IHooks(address(0)),
    //             poolManager: poolManagerA,
    //             fee: 0,
    //             parameters: 0x00
    //         })
    //     );

    //     // make sure vault has enough tokens and ETH to router as router call .settle{value}
    //     CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);

    //     vault.sync(currency1);
    //     currency1.transfer(address(vault), 10 ether);

    //     vm.startPrank(address(router));
    //     vault.lock(hex"21");
    //     vm.stopPrank();

    //     CurrencyLibrary.NATIVE.transfer(address(router), 10 ether);
    //     currency1.transfer(address(vault), 10 ether);
    //     vm.startPrank(address(router));
    //     vault.lock(hex"21");
    //     vm.stopPrank();

    //     // take and settle
    //     {
    //         vm.startPrank(address(router));
    //         vault.lock(hex"22");
    //         vm.stopPrank();
    //     }
    // }

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
