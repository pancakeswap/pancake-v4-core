// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {Ownable} from "../base/Ownable.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "../interfaces/IProtocolFees.sol";

/// @notice ProtocolFeeController for CL Pool type
contract CLProtocolFeeController is IProtocolFeeController, Ownable {
    address public immutable clPoolManager;

    event ProtocolFeeCollected(Currency indexed currency, uint256 amount);

    error InvalidPoolManager();

    constructor(address _clPoolManager) Ownable(msg.sender) {
        clPoolManager = _clPoolManager;
    }

    /// @notice Get the protocol fee for a pool given the conditions of this contract
    /// @return protocolFee The pool's protocol fee, expressed in hundredths of a bip. The upper 12 bits are for 1->0
    function protocolFeeForPool(PoolKey memory poolKey) external pure override returns (uint24 protocolFee) {
        if (poolKey.fee == LPFeeLibrary.DYNAMIC_FEE_FLAG) {
            /// @notice for dynamic fee pools, the default protocol fee is 0.1%
            return _buildProtocolFee(1000);
        } else if (poolKey.fee < 10_000) {
            // For pool between 0% to 1% lpFee, set protocolFee as 30% of the lpFee (rounded down)
            // eg. if pool is 1% lpFee, protocolFee is 0.3%
            //     if pool is 0.25% lpFee, protocolFee is 0.075%
            return _buildProtocolFee(poolKey.fee * 3 / 10);
        } else {
            // for pool above 1% lpFee, set protocolFee as 0.4%
            return _buildProtocolFee(400);
        }
    }

    /// @param fee If 1000, the protocol fee is 0.1%, cap at 0.4%
    function _buildProtocolFee(uint24 fee) internal pure returns (uint24) {
        return fee + (fee << 12);
    }

    /// @notice Override the default protcool fee for the pool
    /// @dev this could be used for marketing campaign where PCS takes 0 protocol fee for a pool for a period
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external onlyOwner {
        if (address(key.poolManager) != clPoolManager) revert InvalidPoolManager();

        IProtocolFees(address(key.poolManager)).setProtocolFee(key, newProtocolFee);
    }

    function collectProtocolFee(address recipient, Currency currency, uint256 amount) external onlyOwner {
        IProtocolFees(clPoolManager).collectProtocolFees(recipient, currency, amount);

        emit ProtocolFeeCollected(currency, amount);
    }
}
