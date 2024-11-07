// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../src/interfaces/IVault.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {CurrencySettlement} from "../helpers/CurrencySettlement.sol";
import {Currency} from "../../src/types/Currency.sol";

contract FakeHook {
    using CurrencySettlement for Currency;

    IVault public vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function take(Currency currency, uint256 amount, bool claims) public {
        currency.take(vault, address(this), amount, claims);
    }

    function settle(Currency currency, uint256 amount, bool burn) public {
        currency.settle(vault, address(this), amount, burn);
    }
}
