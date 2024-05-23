// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {ICLHooks} from "../../../src/pool-cl/interfaces/ICLHooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "../../../src/libraries/LPFeeLibrary.sol";

contract CLDynamicReturnsFeeHook is BaseCLTestHook {
    using LPFeeLibrary for uint24;

    uint24 internal fee;
    ICLPoolManager manager;

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
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

    function setManager(ICLPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function beforeSwap(address, PoolKey calldata, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // attach the fee flag to `fee` to enable overriding the pool's stored fee
        return (ICLHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function forcePoolFeeUpdate(PoolKey calldata _key, uint24 _fee) external {
        manager.updateDynamicLPFee(_key, _fee);
    }
}
