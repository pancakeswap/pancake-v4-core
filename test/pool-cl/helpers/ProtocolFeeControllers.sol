// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {PoolId} from "../../../src/types/PoolId.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";

contract MockProtocolFeeController is IProtocolFeeController {
    mapping(PoolId => uint24) public swapFeeForPool;

    function protocolFeeForPool(PoolKey memory key) external view returns (uint24) {
        return swapFeeForPool[key.toId()];
    }

    // for tests to set pool protocol fees
    function setProtocolFeeForPool(PoolId id, uint24 fee) external {
        swapFeeForPool[id] = fee;
    }
}

contract MaliciousProtocolFeeController {
    function protocolFeeForPool(PoolKey memory) external pure returns (bytes memory payload) {
        /// @dev return a payload that is large enough but not to cause OOG in current calling context
        /// The function should successfully return so that the payload will be copied to the caller
        /// context which maximize the gas consumes and makes it larger than simply running out of gas
        /// in current contex.
        payload = new bytes(230_000);
        payload[payload.length - 1] = 0x01;
    }
}
