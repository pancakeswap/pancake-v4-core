// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurrencyLibrary, Currency} from "../../../src/types/Currency.sol";
import {ILockCallback} from "../../../src/interfaces//ILockCallback.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";

import {BalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";

contract PoolModifyPositionTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IVault public immutable vault;
    ICLPoolManager public immutable manager;

    constructor(IVault _vault, ICLPoolManager _manager) {
        vault = _vault;
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        ICLPoolManager.ModifyLiquidityParams params;
        bytes hookData;
    }

    function modifyPosition(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(vault.lock(abi.encode(CallbackData(msg.sender, key, params, hookData))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(vault));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (BalanceDelta delta, BalanceDelta feeDelta) = manager.modifyLiquidity(data.key, data.params, data.hookData);

        // For now assume to always settle feeDelta in the same way as delta
        BalanceDelta totalDelta = delta + feeDelta;

        if (totalDelta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                vault.settle{value: uint128(totalDelta.amount0())}(data.key.currency0);
            } else {
                IERC20(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(vault), uint128(totalDelta.amount0())
                );
                vault.settle(data.key.currency0);
            }
        }
        if (totalDelta.amount1() > 0) {
            if (data.key.currency1.isNative()) {
                vault.settle{value: uint128(delta.amount1())}(data.key.currency1);
            } else {
                IERC20(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(vault), uint128(totalDelta.amount1())
                );
                vault.settle(data.key.currency1);
            }
        }

        if (totalDelta.amount0() < 0) {
            vault.take(data.key.currency0, data.sender, uint128(-totalDelta.amount0()));
        }
        if (totalDelta.amount1() < 0) {
            vault.take(data.key.currency1, data.sender, uint128(-totalDelta.amount1()));
        }

        return abi.encode(totalDelta);
    }
}
