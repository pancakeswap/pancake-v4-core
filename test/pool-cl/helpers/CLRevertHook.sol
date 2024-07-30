// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BaseCLTestHook} from "./BaseCLTestHook.sol";

contract CLRevertHook is BaseCLTestHook {
    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                befreSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata data)
        external
        pure
        override
        returns (bytes4)
    {
        (bool revertWithHookNotImplemented) = abi.decode(data, (bool));
        if (revertWithHookNotImplemented) {
            revert HookNotImplemented();
        } else {
            revert();
        }
    }
}
