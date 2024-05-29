// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";

contract BinSwapHelper {
    using CurrencyLibrary for Currency;
    using Hooks for bytes32;

    error HookMissingNoOpPermission();

    IBinPoolManager public immutable binManager;
    IVault public immutable vault;

    constructor(IBinPoolManager _binManager, IVault _vault) {
        binManager = _binManager;
        vault = _vault;
    }

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        bool swapForY;
        uint128 amountIn;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    function swap(
        PoolKey memory key,
        bool swapForY,
        uint128 amountIn,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        CallbackData memory data = CallbackData(msg.sender, testSettings, key, swapForY, amountIn, hookData);
        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        require(msg.sender == address(vault));

        CallbackData memory data = abi.decode(callbackData, (CallbackData));

        BalanceDelta delta = binManager.swap(data.key, data.swapForY, data.amountIn, data.hookData);

        if (data.swapForY) {
            if (delta.amount0() < 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency0.isNative()) {
                        vault.settle{value: uint128(-delta.amount0())}(data.key.currency0);
                    } else {
                        vault.sync(data.key.currency0);
                        IERC20(Currency.unwrap(data.key.currency0)).transferFrom(
                            data.sender, address(vault), uint128(-delta.amount0())
                        );
                        vault.settle(data.key.currency0);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    vault.transferFrom(data.sender, address(this), data.key.currency0, uint128(-delta.amount0()));
                    vault.burn(address(this), data.key.currency0, uint128(-delta.amount0()));
                }
            }
            if (delta.amount1() > 0) {
                if (data.testSettings.withdrawTokens) {
                    vault.take(data.key.currency1, data.sender, uint128(delta.amount1()));
                } else {
                    vault.mint(data.sender, data.key.currency1, uint128(delta.amount1()));
                }
            }
        } else {
            if (delta.amount1() < 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency1.isNative()) {
                        vault.settle{value: uint128(-delta.amount1())}(data.key.currency1);
                    } else {
                        vault.sync(data.key.currency1);
                        IERC20(Currency.unwrap(data.key.currency1)).transferFrom(
                            data.sender, address(vault), uint128(-delta.amount1())
                        );
                        vault.settle(data.key.currency1);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    vault.transferFrom(data.sender, address(this), data.key.currency1, uint128(-delta.amount1()));
                    vault.burn(address(this), data.key.currency1, uint128(-delta.amount1()));
                }
            }
            if (delta.amount0() > 0) {
                if (data.testSettings.withdrawTokens) {
                    vault.take(data.key.currency0, data.sender, uint128(delta.amount0()));
                } else {
                    vault.mint(data.sender, data.key.currency0, uint128(delta.amount0()));
                }
            }
        }

        return abi.encode(delta);
    }
}
