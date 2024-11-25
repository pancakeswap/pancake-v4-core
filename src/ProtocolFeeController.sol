// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {Ownable} from "./base/Ownable.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency} from "./types/Currency.sol";
import {LPFeeLibrary} from "./libraries/LPFeeLibrary.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";

/// @notice ProtocolFeeController for both Pool type
contract ProtocolFeeController is IProtocolFeeController, Ownable {
    using ProtocolFeeLibrary for uint24;

    /// @notice throw when the pool manager saved does not match the pool manager from the pool key
    error InvalidPoolManager();

    /// @notice throw when the protocol fee split ratio is invalid i.e. greater than 100%
    error InvliadProtocolFeeSplitRatio();

    /// @notice 100% in hundredths of a bip
    uint256 public constant ONE_HUNDRED_PERCENT_RATIO = 1e6;

    /// @notice The ratio of the protocol fee in the total fee, expressed in hundredths of a bip i.e. 1e4 is 1%
    /// @dev The default value is 33% i.e. protocol fee should be 33% of the total fee
    uint256 public protocolFeeSplitRatio = 33 * 1e4;

    /// @notice The default protocol fee to be used when a pool is initialized
    /// warning: update this value won't affect the existing pools
    /// @dev if not set then the protocol fee is
    ///   1. 0 for dynamic fee pools
    ///   2. a portion of the total fee based on 'protocolFeeSplitRatio' for static fee pools
    mapping(PoolId => uint24) public defaultProtocolFees;

    address public immutable poolManager;

    /// @notice emit when the protocol fee is collected
    event ProtocolFeeCollected(Currency indexed currency, uint256 amount);

    constructor(address _clPoolManager) Ownable(msg.sender) {
        poolManager = _clPoolManager;
    }

    /// @notice Set the ratio of the protocol fee in the total fee
    function setProtocolFeeSplitRatio(uint256 newProtocolFeeSplitRatio) external onlyOwner {
        if (newProtocolFeeSplitRatio > ONE_HUNDRED_PERCENT_RATIO) revert InvliadProtocolFeeSplitRatio();
        protocolFeeSplitRatio = newProtocolFeeSplitRatio;
    }

    function setDefaultProtocolFee(PoolKey memory key, uint24 newProtocolFee) external onlyOwner {
        if (address(key.poolManager) != poolManager) revert InvalidPoolManager();
        /// @notice Validate the protocol fee, revert if fee is over the limit
        if (!newProtocolFee.validate()) revert IProtocolFees.ProtocolFeeTooLarge(newProtocolFee);

        defaultProtocolFees[key.toId()] = newProtocolFee;
    }

    /// @notice Get the protocol fee for a pool given the conditions of this contract
    /// @return protocolFee The pool's protocol fee, expressed in hundredths of a bip. The upper 12 bits are for 1->0
    function protocolFeeForPool(PoolKey memory poolKey) external view override returns (uint24 protocolFee) {
        if (address(poolKey.poolManager) != poolManager) revert InvalidPoolManager();

        // in case we've set a default protocol fee for the pool
        uint24 defaultProtocolFee = defaultProtocolFees[poolKey.toId()];
        if (defaultProtocolFee != 0) {
            // already bi-directional fee so that it can be different in each direction
            return defaultProtocolFee;
        }

        // otherwise, calculate the protocol fee based on the predefined rule
        uint256 lpFee = poolKey.fee;
        if (lpFee == LPFeeLibrary.DYNAMIC_FEE_FLAG) {
            /// @notice for dynamic fee pools, the default protocol fee is 0
            return _buildProtocolFee(0);
        } else {
            /// @notice for static fee pools, the protocol fee should be a portion of the total fee based on 'protocolFeeSplitRatio'
            /// @dev the formula is derived from the following equation:
            /// totalSwapFee = protocolFee + (1 - protocolFee) * lpFee = protocolFee / protocolFeeSplitRatio
            uint24 oneDirectionProtocolFee = uint24(
                lpFee * ONE_HUNDRED_PERCENT_RATIO
                    / (
                        lpFee + ONE_HUNDRED_PERCENT_RATIO * ONE_HUNDRED_PERCENT_RATIO / protocolFeeSplitRatio
                            - ONE_HUNDRED_PERCENT_RATIO
                    )
            );

            // cap the protocol fee at 0.4%, if it's over the limit we set it to the max
            if (oneDirectionProtocolFee > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
                oneDirectionProtocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
            }
            return _buildProtocolFee(oneDirectionProtocolFee);
        }
    }

    /// @param fee If 1000, the protocol fee is 0.1%, cap at 0.4%
    function _buildProtocolFee(uint24 fee) internal pure returns (uint24) {
        return fee + (fee << 12);
    }

    /// @notice Override the default protcool fee for the pool
    /// @dev this could be used for marketing campaign where PCS takes 0 protocol fee for a pool for a period
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external onlyOwner {
        if (address(key.poolManager) != poolManager) revert InvalidPoolManager();

        // no need to validate the protocol fee as it will be done in the pool manager
        IProtocolFees(address(key.poolManager)).setProtocolFee(key, newProtocolFee);
    }

    function collectProtocolFee(address recipient, Currency currency, uint256 amount) external onlyOwner {
        IProtocolFees(poolManager).collectProtocolFees(recipient, currency, amount);

        emit ProtocolFeeCollected(currency, amount);
    }
}
