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

contract BinReturnsDeltaHook is BaseBinTestHook {
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
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: true,
                afterSwapReturnsDelta: true,
                afterMintReturnsDelta: true,
                afterBurnReturnsDelta: true
            })
        );
    }

    function afterMint(
        address,
        PoolKey calldata key,
        IBinPoolManager.MintParams memory params,
        BalanceDelta,
        bytes calldata data
    ) external override returns (bytes4, BalanceDelta) {
        (bytes32 amountIn) = abi.decode(data, (bytes32));
        if (amountIn == 0) {
            return (this.afterMint.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        params.amountIn = amountIn;

        (BalanceDelta hookDelta,) = poolManager.mint(key, params, new bytes(0));
        return (this.afterMint.selector, BalanceDeltaLibrary.ZERO_DELTA - hookDelta);
    }

    function afterBurn(
        address,
        PoolKey calldata key,
        IBinPoolManager.BurnParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        // charge 10% fee
        int128 hookDelta0;
        int128 hookDelta1;
        if (delta.amount0() > 0) {
            hookDelta0 = delta.amount0() / 10;
            vault.take(key.currency0, address(this), uint128(hookDelta0));
        }
        if (delta.amount1() > 0) {
            hookDelta1 = delta.amount1() / 10;
            vault.take(key.currency1, address(this), uint128(hookDelta1));
        }

        return (this.afterBurn.selector, toBalanceDelta(hookDelta0, hookDelta1));
    }

    function beforeSwap(address, PoolKey calldata key, bool swapForY, int128 amountSpecified, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (int128 hookDeltaSpecified, int128 hookDeltaUnspecified,) = abi.decode(data, (int128, int128, int128));

        if (swapForY == amountSpecified < 0) {
            // the specified token is token0
            if (hookDeltaSpecified < 0) key.currency0.settle(vault, address(this), uint128(-hookDeltaSpecified), false);
            if (hookDeltaSpecified > 0) key.currency0.take(vault, address(this), uint128(hookDeltaSpecified), false);

            if (hookDeltaUnspecified < 0) {
                key.currency1.settle(vault, address(this), uint128(-hookDeltaUnspecified), false);
            }
            if (hookDeltaUnspecified > 0) {
                key.currency1.take(vault, address(this), uint128(hookDeltaUnspecified), false);
            }
        } else {
            // the specified token is token1
            if (hookDeltaSpecified < 0) key.currency1.settle(vault, address(this), uint128(-hookDeltaSpecified), false);
            if (hookDeltaSpecified > 0) key.currency1.take(vault, address(this), uint128(hookDeltaSpecified), false);

            if (hookDeltaUnspecified < 0) {
                key.currency0.settle(vault, address(this), uint128(-hookDeltaUnspecified), false);
            }
            if (hookDeltaUnspecified > 0) {
                key.currency0.take(vault, address(this), uint128(hookDeltaUnspecified), false);
            }
        }

        return (this.beforeSwap.selector, toBeforeSwapDelta(hookDeltaSpecified, hookDeltaUnspecified), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        bool swapForY,
        int128 amountSpecified,
        BalanceDelta,
        bytes calldata data
    ) external override returns (bytes4, int128) {
        (,, int128 hookDeltaUnspecified) = abi.decode(data, (int128, int128, int128));

        if (hookDeltaUnspecified == 0) {
            return (this.afterSwap.selector, 0);
        }

        if (swapForY == amountSpecified < 0) {
            // the unspecified token is token1
            if (hookDeltaUnspecified < 0) {
                key.currency1.settle(vault, address(this), uint128(-hookDeltaUnspecified), false);
            }
            if (hookDeltaUnspecified > 0) {
                key.currency1.take(vault, address(this), uint128(hookDeltaUnspecified), false);
            }
        } else {
            // the unspecified token is token0
            if (hookDeltaUnspecified < 0) {
                key.currency0.settle(vault, address(this), uint128(-hookDeltaUnspecified), false);
            }
            if (hookDeltaUnspecified > 0) {
                key.currency0.take(vault, address(this), uint128(hookDeltaUnspecified), false);
            }
        }

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }
}
