// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.10;

import {Encoded} from "./Encoded.sol";

library ParametersHelper {
    using Encoded for bytes32;

    error UnusedBitsNonZero();

    uint256 internal constant OFFSET_HOOK = 0;

    /**
     * @dev Get the hooks registration bitmap from the encoded parameters
     * @param params The encoded parameters, as follows:
     * [0 - 16[: bitmap for hooks registration (16 bits)
     * [16 - 256[: other parameters
     * @return bitmap The bitmap
     */
    function getHooksRegistrationBitmap(bytes32 params) internal pure returns (uint16 bitmap) {
        bitmap = params.decodeUint16(OFFSET_HOOK);
    }

    function checkUnusedBitsAllZero(bytes32 params, uint256 mostSignificantUnUsedBitOffset) internal pure {
        if ((uint256(params) >> (mostSignificantUnUsedBitOffset)) != 0) {
            revert UnusedBitsNonZero();
        }
    }
}
