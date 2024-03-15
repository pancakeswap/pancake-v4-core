// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "../../../src/interfaces/IHooks.sol";

contract HooksContract is IHooks {
    uint16 private immutable bitmap;

    constructor(uint16 _bitmap) {
        bitmap = _bitmap;
    }

    function getHooksRegistrationBitmap() external view override returns (uint16) {
        return bitmap;
    }
}
