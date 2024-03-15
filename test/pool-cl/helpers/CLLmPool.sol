// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ICLLmPool} from "../../../src/pool-cl/interfaces/ICLLmPool.sol";

contract CLLmPool is ICLLmPool {
    function accumulateReward(uint32 currTimestamp) external {}
    function crossLmTick(int24 tick, bool zeroForOne) external {}
}
