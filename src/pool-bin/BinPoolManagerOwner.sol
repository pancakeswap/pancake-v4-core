// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PausableRole} from "../base/PausableRole.sol";
import {IBinPoolManager} from "./interfaces/IBinPoolManager.sol";
import {IPoolManagerOwner} from "../interfaces/IPoolManagerOwner.sol";

/// @dev added interface in this file to avoid polluting other files in repository
interface IBinPoolManagerWithPauseOwnable is IBinPoolManager {
    function pause() external;
    function unpause() external;
    function transferOwnership(address newOwner) external;
}

/**
 * @dev This contract is the owner of the BinPoolManager contract
 *
 * A seperate owner contract is used to handle some functionality so as to reduce the contract size
 * of PoolManager. This allow a higher optimizer run, reducing the gas cost for other poolManager functions
 */
contract BinPoolManagerOwner is IPoolManagerOwner, PausableRole {
    /// @notice Error thrown when owner set min share too small
    error MinShareTooSmall(uint256 minShare);

    IBinPoolManagerWithPauseOwnable public immutable poolManager;

    constructor(IBinPoolManagerWithPauseOwnable _poolManager) {
        poolManager = _poolManager;
    }

    /// @inheritdoc IPoolManagerOwner
    function pausePoolManager() external override onlyPausableRoleOrOwner {
        poolManager.pause();
    }

    /// @inheritdoc IPoolManagerOwner
    function unpausePoolManager() external override onlyOwner {
        poolManager.unpause();
    }

    /// @inheritdoc IPoolManagerOwner
    function setProtocolFeeController(IProtocolFeeController protocolFeeController) external override onlyOwner {
        poolManager.setProtocolFeeController(protocolFeeController);
    }

    /// @inheritdoc IPoolManagerOwner
    function transferPoolManagerOwnership(address newOwner) external override onlyOwner {
        poolManager.transferOwnership(newOwner);
    }

    /// @notice Set max bin steps for binPoolManager, see IBinPoolManager for more documentation about this function
    function setMaxBinStep(uint16 maxBinStep) external onlyOwner {
        poolManager.setMaxBinStep(maxBinStep);
    }

    /// @notice Set max share steps for binPoolManager, see IBinPoolManager for more documentation about this function
    /// @dev Theres an extra check of minBinShare over here, minBinShare before donate should never be 0, otherwise share inflation attack can easily happen
    function setMinBinSharesForDonate(uint256 minBinShare) external onlyOwner {
        if (minBinShare < 1e3) revert MinShareTooSmall(minBinShare);

        poolManager.setMinBinSharesForDonate(minBinShare);
    }
}
