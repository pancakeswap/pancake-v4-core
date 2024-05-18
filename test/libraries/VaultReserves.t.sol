// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {VaultReserves} from "../../src/libraries/VaultReserves.sol";
import {Test} from "forge-std/Test.sol";
import {Currency} from "../../src/types/Currency.sol";

contract VaultReservesTest is Test {
    using VaultReserves for Currency;

    Currency currency0;

    function setUp() public {
        currency0 = Currency.wrap(address(0xabcd));
    }

    function test_getVaultReserves_reverts_withoutSet() public {
        vm.expectRevert(VaultReserves.ReserveNotSync.selector);
        currency0.getVaultReserves();
    }

    function test_getVaultReserves_returns0AfterSet() public {
        currency0.setVaultReserves(0);
        uint256 value = currency0.getVaultReserves();
        assertEq(value, 0);
    }

    function test_getVaultReserves_returns_set() public {
        currency0.setVaultReserves(100);
        uint256 value = currency0.getVaultReserves();
        assertEq(value, 100);
    }

    function test_set_twice_returns_correct_value() public {
        currency0.setVaultReserves(100);
        currency0.setVaultReserves(200);
        uint256 value = currency0.getVaultReserves();
        assertEq(value, 200);
    }

    function test_reservesOfSlot() public {
        assertEq(uint256(keccak256("reservesOfVault")) - 1, VaultReserves.RESERVE_OF_VAULT_SLOT);
    }

    function test_fuzz_get_set(Currency currency, uint256 value) public {
        vm.assume(value != type(uint256).max);
        currency.setVaultReserves(value);
        assertEq(currency.getVaultReserves(), value);
    }
}
