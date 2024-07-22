// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";

contract TokenSender {
    function send(Currency currency, address to, uint256 amount) public {
        currency.transfer(to, amount);
    }
}
