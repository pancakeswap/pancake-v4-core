// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IHooks} from "../../interfaces/IHooks.sol";
import {IBinPoolManager} from "../../pool-bin/interfaces/IBinPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../types/PoolId.sol";
import {PoolKey} from "../../types/PoolKey.sol";

/**
 * @dev A MockHook meant to test Fees functionality
 */
contract MockFeeManagerHook is IHooks {
    using PoolIdLibrary for PoolKey;

    uint16 bitmap;
    uint24 swapfee;

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

    // swap fee for dynamic fee pool is 0 by default, so we need to update it after pool initialization
    function afterInitialize(address, PoolKey calldata key, uint24, bytes calldata) external returns (bytes4) {
        IBinPoolManager(msg.sender).updateDynamicLPFee(key, swapfee);
        return MockFeeManagerHook.afterInitialize.selector;
    }
}
