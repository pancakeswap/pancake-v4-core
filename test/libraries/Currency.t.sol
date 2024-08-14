// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {TokenRejecter} from "../helpers/TokenRejecter.sol";
import {TokenSender} from "../helpers/TokenSender.sol";
import {stdError} from "forge-std/StdError.sol";

contract TestCurrency is Test {
    using CurrencyLibrary for uint256;

    uint256 constant initialERC20Balance = 1000 ether;
    uint256 constant sentBalance = 2 ether;
    address constant otherAddress = address(1);

    Currency nativeCurrency;
    Currency erc20Currency;

    function setUp() public {
        nativeCurrency = Currency.wrap(address(0));
        MockERC20 token = new MockERC20("TestA", "A", 18);
        token.mint(address(this), initialERC20Balance);
        erc20Currency = Currency.wrap(address(token));
        erc20Currency.transfer(address(1), sentBalance);
        nativeCurrency.transfer(address(1), sentBalance);
    }

    function testCurrency_balanceOfSelf_native() public view {
        assertEq(nativeCurrency.balanceOfSelf(), address(this).balance);
    }

    function testCurrency_balanceOfSelf_token() public view {
        assertEq(erc20Currency.balanceOfSelf(), initialERC20Balance - sentBalance);
    }

    function testCurrency_balanceOf_native() public view {
        assertEq(nativeCurrency.balanceOf(otherAddress), sentBalance);
    }

    function testCurrency_balanceOf_token() public view {
        assertEq(erc20Currency.balanceOf(otherAddress), sentBalance);
    }

    function testCurrency_isNative_native_returnsTrue() public view {
        assertEq(nativeCurrency.isNative(), true);
    }

    function testCurrency_isNative_token_returnsFalse() public view {
        assertEq(erc20Currency.isNative(), false);
    }

    function testCurrency_toId_native_returns0() public view {
        assertEq(nativeCurrency.toId(), uint256(0));
    }

    function testCurrency_toId_token_returnsAddressAsUint160() public view {
        assertEq(erc20Currency.toId(), uint256(uint160(Currency.unwrap(erc20Currency))));
    }

    function testCurrency_fromId_native_returns0() public view {
        assertEq(Currency.unwrap(uint256(0).fromId()), Currency.unwrap(nativeCurrency));
    }

    function testCurrency_fromId_token_returnsAddressAsUint160() public view {
        assertEq(
            Currency.unwrap(uint256(uint160(Currency.unwrap(erc20Currency))).fromId()), Currency.unwrap(erc20Currency)
        );
    }

    function testCurrency_transfer_native_successfullyTransfersFunds() public {
        uint256 balanceBefore = otherAddress.balance;
        uint256 senderBalanceBefore = address(this).balance;
        nativeCurrency.transfer(otherAddress, sentBalance);
        uint256 balanceAfter = otherAddress.balance;
        uint256 senderBalanceAfter = address(this).balance;

        assertEq(balanceAfter - balanceBefore, sentBalance);
        assertEq(senderBalanceBefore - senderBalanceAfter, sentBalance);
    }

    function testCurrency_transfer_native_unsuccessfullyTransfersFunds() public {
        address tokenRejector = address(new TokenRejecter());

        /// @dev https://book.getfoundry.sh/cheatcodes/expect-revert
        /// Normally, a call that succeeds returns a status of true (along with any return data) and a call that reverts returns false.
        /// The Solidity compiler will insert checks that ensures that the call succeeded, and revert if it did not.
        /// On low level calls, the expectRevert cheatcode works by making the status boolean
        /// returned by the low level call correspond to whether the expectRevert succeeded or not,
        /// NOT whether or not the low-level call succeeds. Therefore, status being false corresponds to the cheatcode failing.
        /// Apart from this, expectRevert also mangles return data on low level calls, and is not usable.
        vm.expectRevert();
        nativeCurrency.transfer(tokenRejector, sentBalance);
    }

    function testCurrency_transfer_token_successfullyTransfersFunds() public {
        uint256 balanceBefore = erc20Currency.balanceOf(otherAddress);
        uint256 senderBalanceBefore = erc20Currency.balanceOf(address(this));
        erc20Currency.transfer(otherAddress, sentBalance);
        uint256 balanceAfter = erc20Currency.balanceOf(otherAddress);
        uint256 senderBalanceAfter = erc20Currency.balanceOf(address(this));

        assertEq(balanceAfter - balanceBefore, sentBalance);
        assertEq(senderBalanceBefore - senderBalanceAfter, sentBalance);
    }

    function testCurrency_transfer_native_insufficientBalance() public {
        TokenSender sender = new TokenSender();
        deal(address(sender), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(CurrencyLibrary.Wrap__NativeTransferFailed.selector, otherAddress, new bytes(0))
        );
        sender.send(nativeCurrency, otherAddress, 10 ether + 1);
    }

    function testCurrency_transfer_token_insufficientBalance() public {
        TokenSender sender = new TokenSender();
        erc20Currency.transfer(address(sender), 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                CurrencyLibrary.Wrap__ERC20TransferFailed.selector, erc20Currency, stdError.arithmeticError
            )
        );
        sender.send(erc20Currency, otherAddress, 101);
    }
}
