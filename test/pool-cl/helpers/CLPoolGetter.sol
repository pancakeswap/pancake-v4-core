// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CLPoolManager} from "../../../src/pool-cl/CLPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../../src/types/PoolId.sol";
import {CLPool} from "../../../src/pool-cl/libraries/CLPool.sol";

library CLPoolGetter {
    function pools(CLPoolManager manager, PoolId id)
        internal
        view
        returns (
            CLPool.Slot0 memory slot0,
            uint256 feeGrowthGlobal0X128,
            uint256 feeGrowthGlobal1X128,
            uint128 liquidity
        )
    {
        (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee, slot0.lpFee) = manager.getSlot0(id);
        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(id);
        liquidity = manager.getLiquidity(id);
    }
}
