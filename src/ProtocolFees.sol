// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

import {Owner} from "./Owner.sol";
import {Currency} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {IVault} from "./interfaces/IVault.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

abstract contract ProtocolFees is IProtocolFees, Owner {
    using ProtocolFeeLibrary for uint24;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    IProtocolFeeController public protocolFeeController;

    /// @inheritdoc IProtocolFees
    IVault public immutable vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function _setProtocolFee(PoolId id, uint24 newProtocolFee) internal virtual;

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external virtual {
        if (msg.sender != address(protocolFeeController)) revert InvalidCaller();
        if (!newProtocolFee.validate()) revert ProtocolFeeTooLarge(newProtocolFee);
        PoolId id = key.toId();
        _setProtocolFee(id, newProtocolFee);
        emit ProtocolFeeUpdated(id, newProtocolFee);
    }

    /// @notice Fetch the protocol fee for a given pool
    /// @dev Revert if call to protocolFeeController fails or if return value is not 32 bytes
    /// However if the call to protocolFeeController succeed, it can still revert if the return value is too large
    /// @return protocolFee The protocol fee for the pool
    function _fetchProtocolFee(PoolKey memory key) internal returns (uint24 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            address targetProtocolFeeController = address(protocolFeeController);
            bytes memory data = abi.encodeCall(IProtocolFeeController.protocolFeeForPool, (key));

            bool success;
            uint256 returnData;
            assembly ("memory-safe") {
                // only load the first 32 bytes of the return data to prevent gas griefing
                success := call(gas(), targetProtocolFeeController, 0, add(data, 0x20), mload(data), 0, 32)

                // load the return data
                returnData := mload(0)

                // success if return data size is also 32 bytes
                success := and(success, eq(returndatasize(), 32))
            }

            // revert if call fails or return size is not 32 bytes
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(
                    targetProtocolFeeController, bytes4(data), ProtocolFeeCannotBeFetched.selector
                );
            }

            if (returnData == uint24(returnData) && uint24(returnData).validate()) {
                protocolFee = uint24(returnData);
            } else {
                // revert if return value overflow a uint24 or greater than max protocol fee
                revert ProtocolFeeTooLarge(uint24(returnData));
            }
        }
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        override
        returns (uint256 amountCollected)
    {
        if (msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        vault.collectFee(currency, amountCollected, recipient);
    }
}
