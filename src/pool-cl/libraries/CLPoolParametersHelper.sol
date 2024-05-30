// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {Encoded} from "../../libraries/math/Encoded.sol";

/**
 * @title Concentrated Liquidity Pair Parameter Helper Library
 * @dev This library contains functions to get and set parameters of a pair
 * The parameters are stored in a single bytes32 variable in the following format:
 *
 * [0 - 15[: reserve for hooks
 * [16 - 39[: tickSpacing (24 bits)
 */
library CLPoolParametersHelper {
    using Encoded for bytes32;

    uint256 internal constant OFFSET_TICK_SPACING = 16;
    uint256 internal constant OFFSET_FEE = 40;
    /**
     * @dev Get tickSpacing from the encoded pair parameters
     * @param params The encoded pair parameters, as follows:
     * [0 - 16[: hooks registration bitmaps
     * [16 - 39[: tickSpacing (24 bits)
     * [40 - 256[: other parameters
     * [40- 63{: fee (24 bits)}
     * @return tickSpacing The tickSpacing
     */

    function getTickSpacing(bytes32 params) internal pure returns (int24 tickSpacing) {
        tickSpacing = int24(params.decodeUint24(OFFSET_TICK_SPACING));
    }

    function getFee(bytes32 params) internal pure returns (uint24 fee) {
        fee = params.decodeUint24(OFFSET_FEE);
    }

    /**
     * @dev Helper method to set tick spacing in the encoded pair parameter
     * @return The new encoded pair parameter
     */
    function setTickSpacing(bytes32 params, int24 tickSpacing) internal pure returns (bytes32) {
        return params.set(uint24(tickSpacing), Encoded.MASK_UINT24, OFFSET_TICK_SPACING);
    }

    function setFee(bytes32 params, uint24 fee) internal pure returns (bytes32) {
        return params.set(fee, Encoded.MASK_UINT24, OFFSET_FEE);
    }
}
