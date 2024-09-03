// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IHooks} from "../../interfaces/IHooks.sol";
import {Hooks} from "../../libraries/Hooks.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";
import {IBinHooks} from "../../pool-bin/interfaces/IBinHooks.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {IBinPoolManager} from "../../pool-bin/interfaces/IBinPoolManager.sol";

import {console2} from "forge-std/console2.sol";

contract MockBinDynamicFeeHook is IHooks {
    uint16 bitmap;
    uint24 public lpFee;

    function setHooksRegistrationBitmap(uint16 _bitmap) external {
        bitmap = _bitmap;
    }

    function getHooksRegistrationBitmap() external view returns (uint16) {
        return bitmap;
    }

    function setLpFee(uint24 _lpFee) external {
        lpFee = _lpFee;
    }

    function beforeMint(
        address sender,
        PoolKey calldata key,
        IBinPoolManager.MintParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, uint24) {
        console2.log("lpFee: {}", lpFee);

        return (this.beforeMint.selector, lpFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }
}
