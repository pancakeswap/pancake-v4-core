// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/// @title BinPosition
/// @notice Positions represent an owner address' share for a bin
library BinPosition {
    /// @notice Cannot update a position with no liquidity
    error CannotUpdateEmptyPosition();

    // info stored for each user's position
    struct Info {
        // the amount of share owned by this position
        uint256 share;
    }

    /// @notice A helper function to calculate the position key
    /// @param owner The address of the position owner
    /// @param binId The bin id where the position's liquidity is added
    /// @param salt A unique value to differentiate between multiple positions in the same binId, by the same owner. Passed in by the caller.
    function calculatePositionKey(address owner, uint24 binId, bytes32 salt) internal pure returns (bytes32 key) {
        // same as `positionKey = keccak256(abi.encodePacked(owner, binId, salt))`
        // memory will be 12 bytes of zeros, the 20 bytes of address, 3 bytes for uint24
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(add(fmp, 0x23), salt) // [0x23, 0x43)
            mstore(add(fmp, 0x03), binId) // [0x03, 0x23)
            mstore(fmp, owner) // [0x0c, 0x20)
            key := keccak256(add(fmp, 0x0c), 0x37) // len is 55 bytes

            // now clean the memory we used
            mstore(add(fmp, 0x40), 0) // fmp+0x40 held salt
            mstore(add(fmp, 0x20), 0) // fmp+0x20 held binId, salt
            mstore(fmp, 0) // fmp held owner
        }
    }

    /// @notice Returns the Info struct of a position, given an owner and position boundaries
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param binId The bin id where the position's liquidity is added
    /// @param salt The salt to distinguish different positions for the same owner
    /// @return position The position info struct of the given owners' position
    function get(mapping(bytes32 => Info) storage self, address owner, uint24 binId, bytes32 salt)
        internal
        view
        returns (BinPosition.Info storage position)
    {
        bytes32 key = calculatePositionKey(owner, binId, salt);
        position = self[key];
    }

    function addShare(Info storage self, uint256 share) internal {
        self.share += share;
    }

    function subShare(Info storage self, uint256 share) internal {
        self.share -= share;
    }
}
