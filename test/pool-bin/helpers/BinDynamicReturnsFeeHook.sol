// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseBinTestHook} from "./BaseBinTestHook.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {IBinHooks} from "../../../src/pool-bin/interfaces/IBinHooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "../../../src/libraries/LPFeeLibrary.sol";

contract BinDynamicReturnsFeeHook is BaseBinTestHook {
    using LPFeeLibrary for uint24;

    uint24 internal fee;
    IBinPoolManager manager;

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeMint: false,
                afterMint: false,
                beforeBurn: false,
                afterBurn: false,
                beforeSwap: true,
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

    function setManager(IBinPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function beforeSwap(address, PoolKey calldata, bool, int128, bytes calldata)
        external
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // attach the fee flag to `fee` to enable overriding the pool's stored fee
        return (IBinHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function forcePoolFeeUpdate(PoolKey calldata _key, uint24 _fee) external {
        manager.updateDynamicLPFee(_key, _fee);
    }
}
