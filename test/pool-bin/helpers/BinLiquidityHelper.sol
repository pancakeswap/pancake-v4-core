// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

contract BinLiquidityHelper {
    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    error HookMissingNoOpPermission();

    IBinPoolManager public immutable binManager;
    IVault public immutable vault;
    ActionType public actionType;

    enum ActionType {
        Mint,
        Burn
    }

    constructor(IBinPoolManager _binManager, IVault _vault) {
        binManager = _binManager;
        vault = _vault;
    }

    struct BurnCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.BurnParams params;
        bytes hookData;
    }

    struct MintCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.MintParams params;
        bytes hookData;
    }

    function burn(PoolKey memory key, IBinPoolManager.BurnParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        BurnCallbackData memory data = BurnCallbackData(msg.sender, key, params, hookData);
        actionType = ActionType.Burn;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));
    }

    function mint(PoolKey memory key, IBinPoolManager.MintParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        MintCallbackData memory data = MintCallbackData(msg.sender, key, params, hookData);
        actionType = ActionType.Mint;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        require(msg.sender == address(vault));
        BalanceDelta delta;
        PoolKey memory key;
        address sender;

        if (actionType == ActionType.Burn) {
            BurnCallbackData memory data = abi.decode(callbackData, (BurnCallbackData));

            key = data.key;
            sender = data.sender;
            delta = binManager.burn(data.key, data.params, data.hookData);
        } else if (actionType == ActionType.Mint) {
            MintCallbackData memory data = abi.decode(callbackData, (MintCallbackData));

            key = data.key;
            sender = data.sender;
            (delta,) = binManager.mint(data.key, data.params, data.hookData);
        }

        if (delta.amount0() < 0) key.currency0.settle(vault, sender, uint128(-delta.amount0()), false);
        if (delta.amount0() > 0) key.currency0.take(vault, sender, uint128(delta.amount0()), false);
        if (delta.amount1() < 0) key.currency1.settle(vault, sender, uint128(-delta.amount1()), false);
        if (delta.amount1() > 0) key.currency1.take(vault, sender, uint128(delta.amount1()), false);

        return abi.encode(delta);
    }
}
