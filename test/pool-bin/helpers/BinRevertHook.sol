// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BaseBinTestHook} from "./BaseBinTestHook.sol";

contract BinRevertHook is BaseBinTestHook {
    bool public revertWithHookNotImplemented = false;

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeMint: false,
                afterMint: false,
                beforeBurn: false,
                afterBurn: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterMintReturnsDelta: false,
                afterBurnReturnsDelta: false
            })
        );
    }

    function setRevertWithHookNotImplemented(bool value) external {
        revertWithHookNotImplemented = value;
    }

    function afterInitialize(address, PoolKey calldata, uint24) external view override returns (bytes4) {
        if (revertWithHookNotImplemented) {
            revert HookNotImplemented();
        } else {
            revert();
        }
    }
}
