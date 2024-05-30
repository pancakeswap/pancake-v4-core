// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

contract BinDonateHelper {
    using CurrencySettlement for Currency;

    IBinPoolManager public immutable binManager;
    IVault public immutable vault;

    constructor(IBinPoolManager _binManager, IVault _vault) {
        binManager = _binManager;
        vault = _vault;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        uint128 amount0;
        uint128 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        CallbackData memory data = CallbackData(msg.sender, key, amount0, amount1, hookData);
        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        require(msg.sender == address(vault));

        CallbackData memory data = abi.decode(callbackData, (CallbackData));
        PoolKey memory key = data.key;
        address sender = data.sender;

        (BalanceDelta delta,) = binManager.donate(data.key, data.amount0, data.amount1, data.hookData);

        if (delta.amount0() < 0) key.currency0.settle(vault, sender, uint128(-delta.amount0()), false);
        if (delta.amount1() < 0) key.currency1.settle(vault, sender, uint128(-delta.amount1()), false);

        return abi.encode(delta);
    }
}
