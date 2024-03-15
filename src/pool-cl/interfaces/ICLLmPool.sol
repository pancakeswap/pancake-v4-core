//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICLLmPool {
    function accumulateReward(uint32 currTimestamp) external;
    function crossLmTick(int24 tick, bool zeroForOne) external;
}
