// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

contract BinSwapHelper {
    using CurrencySettlement for Currency;
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
                bool burn = !data.testSettings.settleUsingTransfer;
                // transfer VaultToken to vault before calling settle if burn
                if (burn) vault.transferFrom(data.sender, address(this), data.key.currency0, uint128(-delta.amount0()));
                data.key.currency0.settle(vault, data.sender, uint128(-delta.amount0()), burn);
            }

            bool claims = !data.testSettings.withdrawTokens;
            if (delta.amount1() > 0) data.key.currency1.take(vault, data.sender, uint128(delta.amount1()), claims);
        } else {
            if (delta.amount1() < 0) {
                bool burn = !data.testSettings.settleUsingTransfer;
                // transfer VaultToken to vault before calling settle if burn
                if (burn) {
                    vault.transferFrom(data.sender, address(this), data.key.currency1, uint128(-delta.amount1()));
                    data.key.currency1.settle(vault, address(this), uint128(-delta.amount1()), burn);
                } else {
                    data.key.currency1.settle(vault, data.sender, uint128(-delta.amount1()), burn);
                }
            }

            bool claims = !data.testSettings.withdrawTokens;
            if (delta.amount0() > 0) data.key.currency0.take(vault, data.sender, uint128(delta.amount0()), claims);
        }

        return abi.encode(delta);
    }
}
