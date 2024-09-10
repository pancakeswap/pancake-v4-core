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
import {BipsLibrary} from "./libraries/BipsLibrary.sol";

abstract contract ProtocolFees is IProtocolFees, Owner {
    using ProtocolFeeLibrary for uint24;
    using BipsLibrary for uint256;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    IProtocolFeeController public protocolFeeController;

    /// @inheritdoc IProtocolFees
    IVault public immutable vault;

    // a percentage of the block.gaslimit denoted in basis points, used as the gas limit for fee controller calls
    // 100 bps is 1%, at 30M gas, the limit is 300K
    uint256 private constant BLOCK_LIMIT_BPS = 100;

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

    /// @notice Fetch the protocol fee for a given pool, returning false if the call fails or the returned fee is invalid.
    /// @dev to prevent an invalid protocol fee controller from blocking pools from being initialized
    ///      the success of this function is NOT checked on initialize and if the call fails, the protocol fee is set to 0.
    /// @dev the success of this function must be checked when called in setProtocolFee
    function _fetchProtocolFee(PoolKey memory key) internal returns (bool success, uint24 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            uint256 controllerGasLimit = block.gaslimit.calculatePortion(BLOCK_LIMIT_BPS);

            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();

            address targetProtocolFeeController = address(protocolFeeController);
            bytes memory data = abi.encodeCall(IProtocolFeeController.protocolFeeForPool, (key));
            uint256 returnData;
            assembly ("memory-safe") {
                // only load the first 32 bytes of the return data to prevent gas griefing
                success := call(controllerGasLimit, targetProtocolFeeController, 0, add(data, 0x20), mload(data), 0, 32)
                // if success is false this wont actually be returned, instead 0 will be returned
                returnData := mload(0)

                // success if return data size is 32 bytes
                success := and(success, eq(returndatasize(), 32))
            }

            (success, protocolFee) = success && (returnData == uint24(returnData)) && uint24(returnData).validate()
                ? (true, uint24(returnData))
                : (false, 0);
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
        if (msg.sender != owner() && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        vault.collectFee(currency, amountCollected, recipient);
    }
}
