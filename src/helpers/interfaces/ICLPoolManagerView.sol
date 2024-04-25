//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CLPool} from "../../pool-cl/libraries/CLPool.sol";
import {PoolId} from "../../types/PoolId.sol";

interface ICLPoolManagerView {
    struct CLPoolState {
        CLPool.Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;
    }

    // mapping(PoolId id => CLPool.State) public pools;
    function pools(PoolId id) external view returns (CLPoolState memory);

    // mapping(uint256 => PoolId id) public poolIds;
    function poolIds(uint256 index) external view returns (PoolId);
}
