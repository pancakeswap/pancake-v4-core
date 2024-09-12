//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPausable {
    /// @notice pause pool manager. This will stop all swaps, mint, and donate, leaving just remove liquidity functionality.
    function pause() external;

    /// @notice unpause pool manager. This will allow all functionality to be used again.
    function unpause() external;
}
