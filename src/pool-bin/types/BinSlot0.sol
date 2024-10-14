// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev BinSlot0 is a packed version of solidity structure.
 * Using the packaged version saves gas by not storing the structure fields in memory slots.
 *
 * Layout:
 * 184 bits empty | 24 bits lpFee | 12 bits protocolFee 1->0 | 12 bits protocolFee 0->1 | 24 bits activeId
 *
 * Fields in the direction from the least significant bit:
 *
 * The current activeId
 * uint24 activeId;
 *
 * Protocol fee, expressed in hundredths of a bip, upper 12 bits are for 1->0, and the lower 12 are for 0->1
 * the maximum is 1000 - meaning the maximum protocol fee is 0.1%
 * the protocolFee is taken from the input first, then the lpFee is taken from the remaining input
 * uint24 protocolFee;
 *
 * The current LP fee of the pool. If the pool is dynamic, this does not include the dynamic fee flag.
 * uint24 lpFee;
 */
type BinSlot0 is bytes32;

using BinSlot0Library for BinSlot0 global;

/// @notice Library for getting and setting values in the Slot0 type
library BinSlot0Library {
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant PROTOCOL_FEE_OFFSET = 24;
    uint8 internal constant LP_FEE_OFFSET = 48;

    ////////////////////////////////////////////////////////////////////////////////////////
    // #### GETTERS ####
    ////////////////////////////////////////////////////////////////////////////////////////
    function activeId(BinSlot0 _packed) internal pure returns (uint24 _activeId) {
        assembly ("memory-safe") {
            _activeId := and(MASK_24_BITS, _packed)
        }
    }

    function protocolFee(BinSlot0 _packed) internal pure returns (uint24 _protocolFee) {
        assembly ("memory-safe") {
            _protocolFee := and(MASK_24_BITS, shr(PROTOCOL_FEE_OFFSET, _packed))
        }
    }

    function lpFee(BinSlot0 _packed) internal pure returns (uint24 _lpFee) {
        assembly ("memory-safe") {
            _lpFee := and(MASK_24_BITS, shr(LP_FEE_OFFSET, _packed))
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    // #### SETTERS ####
    ////////////////////////////////////////////////////////////////////////////////////////
    function setActiveId(BinSlot0 _packed, uint24 _activeId) internal pure returns (BinSlot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_24_BITS), _packed), and(MASK_24_BITS, _activeId))
        }
    }

    function setProtocolFee(BinSlot0 _packed, uint24 _protocolFee) internal pure returns (BinSlot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(PROTOCOL_FEE_OFFSET, MASK_24_BITS)), _packed),
                    shl(PROTOCOL_FEE_OFFSET, and(MASK_24_BITS, _protocolFee))
                )
        }
    }

    function setLpFee(BinSlot0 _packed, uint24 _lpFee) internal pure returns (BinSlot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(LP_FEE_OFFSET, MASK_24_BITS)), _packed), shl(LP_FEE_OFFSET, and(MASK_24_BITS, _lpFee)))
        }
    }
}
