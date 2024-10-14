// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CLPoolManager} from "../../../src/pool-cl/CLPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../../src/types/PoolId.sol";
import {CLPool} from "../../../src/pool-cl/libraries/CLPool.sol";
import {CLSlot0} from "../../../src/pool-cl/types/CLSlot0.sol";

library CLPoolGetter {
    function pools(CLPoolManager manager, PoolId id)
        internal
        view
        returns (CLSlot0 slot0, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, uint128 liquidity)
    {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(id);
        slot0 = CLSlot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setProtocolFee(protocolFee)
            .setLpFee(lpFee);
        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(id);
        liquidity = manager.getLiquidity(id);
    }
}
