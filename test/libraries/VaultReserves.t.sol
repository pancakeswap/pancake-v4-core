// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {VaultReserve} from "../../src/libraries/VaultReserve.sol";
import {Test} from "forge-std/Test.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";

contract VaultReserveTest is Test {
    Currency currency0;

    function setUp() public {
        currency0 = Currency.wrap(address(0xabcd));
    }

    function test_alreadySettledLastSync() public {
        VaultReserve.alreadySettledLastSync();

        VaultReserve.setVaultReserve(currency0, 10);
        vm.expectRevert(VaultReserve.LastSyncNotSettled.selector);
        VaultReserve.alreadySettledLastSync();

        VaultReserve.setVaultReserve(currency0, 0);
        VaultReserve.alreadySettledLastSync();
    }

    function test_slot_correctness() public pure {
        assertEq(uint256(keccak256("reserveType")) - 1, VaultReserve.RESERVE_TYPE_SLOT);
        assertEq(uint256(keccak256("reserveAmount")) - 1, VaultReserve.RESERVE_AMOUNT_SLOT);
    }

    function test_fuzz_get_set(Currency currency, uint256 amount) public {
        (Currency currencyBefore, uint256 amountBefore) = VaultReserve.getVaultReserve();
        assertEq(Currency.unwrap(currencyBefore), Currency.unwrap(CurrencyLibrary.NATIVE));
        assertEq(amountBefore, 0);

        VaultReserve.setVaultReserve(currency, amount);
        (Currency currencyAfter, uint256 amountAfter) = VaultReserve.getVaultReserve();
        assertEq(Currency.unwrap(currencyAfter), Currency.unwrap(currency));
        assertEq(amountAfter, amount);
    }
}
