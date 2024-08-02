// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "../../src/types/Currency.sol";

library SortTokens {
    function sort(MockERC20 tokenA, MockERC20 tokenB)
        internal
        pure
        returns (Currency _currency0, Currency _currency1)
    {
        if (address(tokenA) < address(tokenB)) {
            (_currency0, _currency1) = (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));
        } else {
            (_currency0, _currency1) = (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        }
    }

    function sort(MockERC20 token0, MockERC20 token1, MockERC20 token2)
        internal
        pure
        returns (Currency _currency0, Currency _currency1, Currency _currency2)
    {
        if (address(token0) > address(token1) && address(token0) > address(token2)) {
            _currency2 = Currency.wrap(address(token0));
            (_currency0, _currency1) = sort(token1, token2);
        } else if (address(token1) > address(token0) && address(token1) > address(token2)) {
            _currency2 = Currency.wrap(address(token1));
            (_currency0, _currency1) = sort(token0, token2);
        } else {
            _currency2 = Currency.wrap(address(token2));
            (_currency0, _currency1) = sort(token0, token1);
        }
    }
}
