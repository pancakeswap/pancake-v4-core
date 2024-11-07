// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {BaseBinTestHook} from "./BaseBinTestHook.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";

import {console2} from "forge-std/console2.sol";

/// @dev A hook which take a fee on every mint/burn
contract BinMintBurnFeeHook is BaseBinTestHook {
    error InvalidAction();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    IBinPoolManager public immutable poolManager;

    constructor(IVault _vault, IBinPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeMint: false,
                afterMint: true,
                beforeBurn: false,
                afterBurn: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterMintReturnsDelta: true,
                afterBurnReturnsDelta: true
            })
        );
    }

    /// @dev take 2x of the mint amount as fee
    /// meant for https://github.com/pancakeswap/pancake-v4-core/pull/203 to ensure reserveOfApp underflow won't happen
    function afterMint(
        address,
        PoolKey calldata key,
        IBinPoolManager.MintParams calldata,
        BalanceDelta delta,
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
        return (this.afterMint.selector, hookDelta);
    }

    /// @dev take 4x the burn amount as fee
    /// meant for https://github.com/pancakeswap/pancake-v4-core/pull/203 to ensure reserveOfApp underflow won't happen
    function afterBurn(
        address,
        PoolKey calldata key,
        IBinPoolManager.BurnParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        console2.log("afterBurn delta");
        console2.logInt(delta.amount0());
        console2.logInt(delta.amount1());

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
        return (this.afterBurn.selector, hookDelta);
    }
}
