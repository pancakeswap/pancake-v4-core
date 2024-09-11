// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IVault} from "../interfaces/IVault.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ProtocolFees} from "../ProtocolFees.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "../libraries/ProtocolFeeLibrary.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/**
 * @dev A MockFeePoolManager meant to test Fees functionality
 */
contract MockFeePoolManager is ProtocolFees {
    using FixedPointMathLib for uint256;

    mapping(PoolId poolId => BalanceDelta delta) public balanceDeltaOfPool;
    mapping(PoolId id => Slot0) public pools;

    struct Slot0 {
        uint24 protocolFee;
    }

    constructor(IVault vault, uint256 controllerGasLimit) ProtocolFees(vault) {}

    function initialize(PoolKey memory key, bytes calldata) external {
        PoolId id = key.toId();

        uint24 protocolFee = _fetchProtocolFee(key);

        pools[id] = Slot0({protocolFee: protocolFee});
    }

    function swap(PoolKey memory key, uint256 amt0Fee, uint256 amt1Fee)
        public
        returns (uint256 protocolFee0, uint256 protocolFee1)
    {
        return mockAction(key, amt0Fee, amt1Fee, true);
    }

    function withdraw(PoolKey memory key, uint256 amt0Fee, uint256 amt1Fee)
        public
        returns (uint256 protocolFee0, uint256 protocolFee1)
    {
        return mockAction(key, amt0Fee, amt1Fee, false);
    }

    /**
     * @dev mock an anction (swap or withdrawal)
     *
     */
    function mockAction(PoolKey memory key, uint256 amt0Fee, uint256 amt1Fee, bool isSwap)
        public
        returns (uint256 protocolFee0, uint256 protocolFee1)
    {
        PoolId id = key.toId();
        Slot0 memory slot0 = pools[id];

        // Similar to uni-v4 logic (deduct protocolFee portion first)
        uint24 protocolFee = isSwap ? slot0.protocolFee : 0;

        if (protocolFee > 0) {
            if ((protocolFee % 4096) > 0) {
                protocolFee0 = amt0Fee * (protocolFee % 4096) / ProtocolFeeLibrary.PIPS_DENOMINATOR;
                amt0Fee -= protocolFee0;
                protocolFeesAccrued[key.currency0] += protocolFee0;
            }

            if ((protocolFee >> 12) > 0) {
                protocolFee1 = amt1Fee * (protocolFee >> 12) / ProtocolFeeLibrary.PIPS_DENOMINATOR;
                amt1Fee -= protocolFee1;
                protocolFeesAccrued[key.currency1] += protocolFee1;
            }
        }
    }

    function getProtocolFee(PoolKey memory key) external view returns (uint24) {
        return pools[key.toId()].protocolFee;
    }

    function _setProtocolFee(PoolId id, uint24 newProtocolFee) internal override {
        pools[id].protocolFee = newProtocolFee;
    }
}
