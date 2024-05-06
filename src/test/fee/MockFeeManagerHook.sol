// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "../../interfaces/IHooks.sol";
import {IBinDynamicFeeManager} from "../../pool-bin/interfaces/IBinDynamicFeeManager.sol";
import {IBinPoolManager} from "../../pool-bin/interfaces/IBinPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../types/PoolId.sol";
import {PoolKey} from "../../types/PoolKey.sol";

/**
 * @dev A MockHook meant to test Fees functionality
 */
contract MockFeeManagerHook is IHooks, IBinDynamicFeeManager {
    using PoolIdLibrary for PoolKey;

    uint16 bitmap;
    uint24 swapfee;
    uint24 swapfeeForSwapInSwapOut;

    function setHooksRegistrationBitmap(uint16 _bitmap) external {
        bitmap = _bitmap;
    }

    function getHooksRegistrationBitmap() external view returns (uint16) {
        return bitmap;
    }

    function setSwapFee(uint24 _swapfee) external {
        swapfee = _swapfee;
    }

    function getFee(address, PoolKey calldata) external view returns (uint24) {
        return swapfee;
    }

    function setFeeForSwapInSwapOut(uint24 _swapFee) external {
        swapfeeForSwapInSwapOut = _swapFee;
    }

    function getFeeForSwapInSwapOut(address, PoolKey calldata, bool, uint128, uint128) external view returns (uint24) {
        return swapfeeForSwapInSwapOut;
    }

    // swap fee for dynamic fee pool is 0 by default, so we need to update it after pool initialization
    function afterInitialize(address, PoolKey calldata key, uint24, bytes calldata) external returns (bytes4) {
        IBinPoolManager(msg.sender).updateDynamicLPFee(key, swapfee);
        return MockFeeManagerHook.afterInitialize.selector;
    }
}
