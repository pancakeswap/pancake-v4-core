// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency} from "./types/Currency.sol";
import {LPFeeLibrary} from "./libraries/LPFeeLibrary.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";

/// @notice ProtocolFeeController for both Pool type
contract ProtocolFeeController is IProtocolFeeController, Ownable2Step {
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

    /// @notice Get the protocol fee for a pool given the conditions of this contract
    /// @return protocolFee The pool's protocol fee, expressed in hundredths of a bip. The upper 12 bits are for 1->0
    function protocolFeeForPool(PoolKey memory poolKey) external view override returns (uint24 protocolFee) {
        if (address(poolKey.poolManager) != poolManager) revert InvalidPoolManager();

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
    /// @return The protocol fee for both directions, the upper 12 bits are for 1->0
    function _buildProtocolFee(uint24 fee) internal pure returns (uint24) {
        return fee + (fee << 12);
    }

    /// @notice Override the default protcool fee for the pool
    /// @dev this could be used for marketing campaign where PCS takes 0 protocol fee for a pool for a period
    /// @param newProtocolFee 1000 = 0.1%, and max at 4000 = 0.4%. If set at 0.1%, this means 0.1% of amountIn for each swap will go to protocol
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