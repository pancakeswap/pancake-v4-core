// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity 0.8.26;

import {IPoolManagerOwner} from "../interfaces/IPoolManagerOwner.sol";

/**
 * @notice dev This contract implements "Ownable2Step styled" poolManager ownership transfer
 * functionality. Namely an extra acceptance step is added to the ownership transfer process.
 * This is done to prevent accidental ownership transfer to a wrong address.
 */
abstract contract PoolManagerOwnable2Step is IPoolManagerOwner {
    error NotPendingPoolManagerOwner();

    event PoolManagerOwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event PoolManagerOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address private _pendingPoolManagerOwner;

    modifier onlyPendingPoolManagerOwner() {
        if (_pendingPoolManagerOwner != msg.sender) {
            revert NotPendingPoolManagerOwner();
        }

        _;
    }

    function _setPendingPoolManagerOwner(address newPoolManagerOwner) internal {
        _pendingPoolManagerOwner = newPoolManagerOwner;
    }

    /// @inheritdoc IPoolManagerOwner
    function pendingPoolManagerOwner() public view override returns (address) {
        return _pendingPoolManagerOwner;
    }
}
