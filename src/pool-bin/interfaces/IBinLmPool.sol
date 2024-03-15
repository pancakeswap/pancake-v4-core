//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBinLmPool {
    function accumulateReward(uint32 currTimestamp) external;
}
