// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurrencyLibrary, Currency} from "../../../src/types/Currency.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {ILockCallback} from "../../../src/interfaces//ILockCallback.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";

import {BalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";

contract PoolModifyPositionTest is ILockCallback {
    using CurrencySettlement for Currency;

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
            data.key.currency0.settle(vault, data.sender, uint128(totalDelta.amount0()), false);
        }
        if (totalDelta.amount1() > 0) {
            data.key.currency1.settle(vault, data.sender, uint128(totalDelta.amount1()), false);
        }

        if (totalDelta.amount0() < 0) {
            data.key.currency0.take(vault, data.sender, uint128(-totalDelta.amount0()), false);
        }
        if (totalDelta.amount1() < 0) {
            data.key.currency1.take(vault, data.sender, uint128(-totalDelta.amount0()), false);
        }

        return abi.encode(totalDelta);
    }
}
