// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

contract CLMintBurnFeeHook is BaseCLTestHook {
    error InvalidAction();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;

    constructor(IVault _vault, ICLPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                befreSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: true,
                afterRemoveLiquidityReturnsDelta: true
            })
        );
    }

    /// @dev take 2x of the mint amount as fee
    /// meant for https://github.com/pancakeswap/infinity-core/pull/203 to ensure reserveOfApp underflow won't happen
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta, // ignore fee delta for this case
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        // take fee from mint
        int128 amt0Fee;
        if (delta.amount0() < 0) {
            amt0Fee = (-delta.amount0()) * 2;
            key.currency0.take(vault, address(this), uint128(amt0Fee), true);
        }
        int128 amt1Fee = 0;
        if (delta.amount1() < 0) {
            amt1Fee = (-delta.amount1()) * 2;
            key.currency1.take(vault, address(this), uint128(amt1Fee), true);
        }

        BalanceDelta hookDelta = toBalanceDelta(amt0Fee, amt1Fee);
        return (this.afterAddLiquidity.selector, hookDelta);
    }

    /// @dev take 4x the burn amount as fee
    /// meant for https://github.com/pancakeswap/infinity-core/pull/203 to ensure reserveOfApp underflow won't happen
    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta, // ignore fee delta for this case
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        int128 amt0Fee;
        if (delta.amount0() > 0) {
            amt0Fee = (delta.amount0()) * 4;
            key.currency0.take(vault, address(this), uint128(amt0Fee), true);
        }
        int128 amt1Fee = 0;
        if (delta.amount1() > 0) {
            amt1Fee = (delta.amount1()) * 4;
            key.currency1.take(vault, address(this), uint128(amt1Fee), true);
        }

        BalanceDelta hookDelta = toBalanceDelta(amt0Fee, amt1Fee);
        return (this.afterRemoveLiquidity.selector, hookDelta);
    }
}
