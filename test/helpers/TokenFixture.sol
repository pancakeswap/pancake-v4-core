// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency} from "../../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "./SortTokens.sol";

contract TokenFixture {
    Currency internal currency0;
    Currency internal currency1;

    function initializeTokens() internal {
        MockERC20 tokenA = new MockERC20("TestA", "A", 18);
        MockERC20 tokenB = new MockERC20("TestB", "B", 18);

        tokenA.mint(address(this), 1000 ether);
        tokenB.mint(address(this), 1000 ether);

        (currency0, currency1) = SortTokens.sort(tokenA, tokenB);
    }

    function mint(uint256 amount) public {
        MockERC20 tokenA = MockERC20(Currency.unwrap(currency0));
        MockERC20 tokenB = MockERC20(Currency.unwrap(currency1));

        tokenA.mint(address(this), amount);
        tokenB.mint(address(this), amount);
    }
}
