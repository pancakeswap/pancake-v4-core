// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {PausableRole} from "./PausableRole.sol";
import {Currency} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {IVault} from "./interfaces/IVault.sol";

abstract contract ProtocolFees is IProtocolFees, PausableRole {
    using PoolIdLibrary for PoolKey;
    using ProtocolFeeLibrary for uint24;

    mapping(Currency currency => uint256) public protocolFeesAccrued;

    IProtocolFeeController public protocolFeeController;
    IVault public immutable vault;

    uint256 private immutable controllerGasLimit;

    constructor(IVault _vault, uint256 _controllerGasLimit) {
        vault = _vault;
        controllerGasLimit = _controllerGasLimit;
    }

    function _setProtocolFee(PoolId id, uint24 newProtocolFee) internal virtual;

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external virtual {
        if (msg.sender != address(protocolFeeController)) revert InvalidCaller();
        if (!newProtocolFee.validate()) revert FeeTooLarge();
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
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();

            (bool _success, bytes memory _data) = address(protocolFeeController).call{gas: controllerGasLimit}(
                abi.encodeCall(IProtocolFeeController.protocolFeeForPool, (key))
            );
            // Ensure that the return data fits within a word
            if (!_success || _data.length > 32) return (false, 0);

            uint256 returnData;
            assembly {
                returnData := mload(add(_data, 0x20))
            }

            // Ensure return data does not overflow a uint24 and that the underlying fees are within bounds.
            (success, protocolFee) = (returnData == uint24(returnData)) && uint24(returnData).validate()
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
