// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../../../src/types/Currency.sol";
import {IPoolManager} from "../../../src/interfaces/IPoolManager.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

contract CLPoolManagerRouter {
    error InvalidAction();
    error HookMissingNoOpPermission();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;

    constructor(IVault _vault, ICLPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    struct CallbackData {
        bytes action;
        bytes rawCallbackData;
    }

    struct ModifyPositionCallbackData {
        address sender;
        PoolKey key;
        ICLPoolManager.ModifyLiquidityParams params;
        bytes hookData;
    }

    function modifyPosition(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta, BalanceDelta feeDelta) {
        (delta, feeDelta) = abi.decode(
            vault.lock(
                abi.encode("modifyPosition", abi.encode(ModifyPositionCallbackData(msg.sender, key, params, hookData)))
            ),
            (BalanceDelta, BalanceDelta)
        );

        // if any ethers left
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function modifyPositionCallback(bytes memory rawData) private returns (bytes memory) {
        ModifyPositionCallbackData memory data = abi.decode(rawData, (ModifyPositionCallbackData));

        // delta already takes feeDelta into account
        (BalanceDelta delta, BalanceDelta feeDelta) = poolManager.modifyLiquidity(data.key, data.params, data.hookData);

        if (delta.amount0() < 0) data.key.currency0.settle(vault, data.sender, uint128(-delta.amount0()), false);
        if (delta.amount1() < 0) data.key.currency1.settle(vault, data.sender, uint128(-delta.amount1()), false);
        if (delta.amount0() > 0) data.key.currency0.take(vault, data.sender, uint128(delta.amount0()), false);
        if (delta.amount1() > 0) data.key.currency1.take(vault, data.sender, uint128(delta.amount1()), false);

        return abi.encode(delta, feeDelta);
    }

    struct SwapTestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    struct SwapCallbackData {
        address sender;
        SwapTestSettings testSettings;
        PoolKey key;
        ICLPoolManager.SwapParams params;
        bytes hookData;
    }

    function swap(
        PoolKey memory key,
        ICLPoolManager.SwapParams memory params,
        SwapTestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            vault.lock(
                abi.encode("swap", abi.encode(SwapCallbackData(msg.sender, testSettings, key, params, hookData)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function swapCallback(bytes memory rawData) private returns (bytes memory) {
        SwapCallbackData memory data = abi.decode(rawData, (SwapCallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);

        if (data.params.zeroForOne) {
            if (delta.amount0() < 0) {
                bool burn = !data.testSettings.settleUsingTransfer;
                if (burn) {
                    vault.transferFrom(data.sender, address(this), data.key.currency0, uint128(-delta.amount0()));
                    data.key.currency0.settle(vault, address(this), uint128(-delta.amount0()), burn);
                } else {
                    data.key.currency0.settle(vault, data.sender, uint128(-delta.amount0()), burn);
                }
            }

            bool claims = !data.testSettings.withdrawTokens;
            if (delta.amount1() > 0) data.key.currency1.take(vault, data.sender, uint128(delta.amount1()), claims);
        } else {
            if (delta.amount1() < 0) {
                bool burn = !data.testSettings.settleUsingTransfer;
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

    struct DonateCallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            vault.lock(
                abi.encode("donate", abi.encode(DonateCallbackData(msg.sender, key, amount0, amount1, hookData)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function donateCallback(bytes memory rawData) private returns (bytes memory) {
        DonateCallbackData memory data = abi.decode(rawData, (DonateCallbackData));

        BalanceDelta delta = poolManager.donate(data.key, data.amount0, data.amount1, data.hookData);

        if (delta.amount0() < 0) data.key.currency0.settle(vault, data.sender, uint128(-delta.amount0()), false);
        if (delta.amount1() < 0) data.key.currency1.settle(vault, data.sender, uint128(-delta.amount1()), false);

        return abi.encode(delta);
    }

    struct TakeCallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function take(PoolKey memory key, uint256 amount0, uint256 amount1) external payable {
        vault.lock(abi.encode("take", abi.encode(TakeCallbackData(msg.sender, key, amount0, amount1))));
    }

    function takeCallback(bytes memory rawData) private returns (bytes memory) {
        TakeCallbackData memory data = abi.decode(rawData, (TakeCallbackData));

        if (data.amount0 > 0) {
            uint256 balBefore = data.key.currency0.balanceOf(data.sender);
            vault.take(data.key.currency0, data.sender, data.amount0);
            uint256 balAfter = data.key.currency0.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount0);

            data.key.currency0.settle(vault, data.sender, uint128(data.amount0), false);
        }

        if (data.amount1 > 0) {
            uint256 balBefore = data.key.currency1.balanceOf(data.sender);
            vault.take(data.key.currency1, data.sender, data.amount1);
            uint256 balAfter = data.key.currency1.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount1);

            data.key.currency1.settle(vault, data.sender, uint128(data.amount1), false);
        }

        return abi.encode(0);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(vault));

        (bytes memory action, bytes memory rawCallbackData) = abi.decode(data, (bytes, bytes));
        if (keccak256(action) == keccak256("modifyPosition")) {
            return modifyPositionCallback(rawCallbackData);
        } else if (keccak256(action) == keccak256("swap")) {
            return swapCallback(rawCallbackData);
        } else if (keccak256(action) == keccak256("donate")) {
            return donateCallback(rawCallbackData);
        } else if (keccak256(action) == keccak256("take")) {
            return takeCallback(rawCallbackData);
        } else {
            revert InvalidAction();
        }
    }
}
