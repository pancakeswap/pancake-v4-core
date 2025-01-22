// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IProtocolFeeController} from "../../interfaces/IProtocolFeeController.sol";
import {PoolId} from "../../types/PoolId.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {ProtocolFeeLibrary} from "../../libraries/ProtocolFeeLibrary.sol";

/**
 * @dev A MockProtocolFeeController meant to test Fees functionality
 */
contract MockProtocolFeeController is IProtocolFeeController {
    mapping(PoolId id => uint24 fee) public protocolFee;

    function setProtocolFeeForPool(PoolKey memory key, uint24 fee) public {
        PoolId id = key.toId();
        protocolFee[id] = fee;
    }

    function protocolFeeForPool(PoolKey memory key) external view returns (uint24) {
        PoolId id = key.toId();
        return protocolFee[id];
    }
}

/// @notice Reverts on call
contract RevertingMockProtocolFeeController is IProtocolFeeController {
    error DevsBlock();

    function protocolFeeForPool(PoolKey memory /* key */ ) external pure returns (uint24) {
        revert DevsBlock();
    }
}

/// @notice Returns an out of bounds protocol fee
contract OutOfBoundsMockProtocolFeeController is IProtocolFeeController {
    function protocolFeeForPool(PoolKey memory /* key */ ) external pure returns (uint24) {
        return ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1;
    }
}

/// @notice Return a value that overflows a uint24
contract OverflowMockProtocolFeeController is IProtocolFeeController {
    function protocolFeeForPool(PoolKey memory /* key */ ) external pure returns (uint24) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0xFFFFFFFFAAA001)
            return(ptr, 0x20)
        }
    }
}

/// @notice Returns data that is larger than a word
contract InvalidReturnSizeMockProtocolFeeController is IProtocolFeeController {
    function protocolFeeForPool(PoolKey memory /* key */ ) external view returns (uint24) {
        address a = address(this);
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, a)
            mstore(add(ptr, 0x20), a)
            return(ptr, 0x40)
        }
    }
}
