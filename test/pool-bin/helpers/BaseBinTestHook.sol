// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../../src/pool-bin/interfaces/IBinHooks.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {IBinHooks} from "../../../src/pool-bin/interfaces/IBinHooks.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";

contract BaseBinTestHook is IBinHooks {
    error HookNotImplemented();

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeMint;
        bool afterMint;
        bool beforeBurn;
        bool afterBurn;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool beforeSwapReturnsDelta;
        bool afterSwapReturnsDelta;
        bool afterMintReturnsDelta;
        bool afterBurnReturnsDelta;
    }

    function getHooksRegistrationBitmap() external view virtual returns (uint16) {
        revert HookNotImplemented();
    }

    function beforeInitialize(address, PoolKey calldata, uint24, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint24, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeMint(address, PoolKey calldata, IBinPoolManager.MintParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterMint(address, PoolKey calldata, IBinPoolManager.MintParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        returns (bytes4, BalanceDelta)
    {
        revert HookNotImplemented();
    }

    function beforeBurn(address, PoolKey calldata, IBinPoolManager.BurnParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterBurn(address, PoolKey calldata, IBinPoolManager.BurnParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        returns (bytes4, BalanceDelta)
    {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, bool, int128, bytes calldata)
        external
        virtual
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, bool, int128, BalanceDelta, bytes calldata)
        external
        virtual
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function _hooksRegistrationBitmapFrom(Permissions memory permissions) internal pure returns (uint16) {
        return uint16(
            (permissions.beforeInitialize ? 1 << HOOKS_BEFORE_INITIALIZE_OFFSET : 0)
                | (permissions.afterInitialize ? 1 << HOOKS_AFTER_INITIALIZE_OFFSET : 0)
                | (permissions.beforeMint ? 1 << HOOKS_BEFORE_MINT_OFFSET : 0)
                | (permissions.afterMint ? 1 << HOOKS_AFTER_MINT_OFFSET : 0)
                | (permissions.beforeBurn ? 1 << HOOKS_BEFORE_BURN_OFFSET : 0)
                | (permissions.afterBurn ? 1 << HOOKS_AFTER_BURN_OFFSET : 0)
                | (permissions.beforeSwap ? 1 << HOOKS_BEFORE_SWAP_OFFSET : 0)
                | (permissions.afterSwap ? 1 << HOOKS_AFTER_SWAP_OFFSET : 0)
                | (permissions.beforeDonate ? 1 << HOOKS_BEFORE_DONATE_OFFSET : 0)
                | (permissions.afterDonate ? 1 << HOOKS_AFTER_DONATE_OFFSET : 0)
                | (permissions.beforeSwapReturnsDelta ? 1 << HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET : 0)
                | (permissions.afterSwapReturnsDelta ? 1 << HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET : 0)
                | (permissions.afterMintReturnsDelta ? 1 << HOOKS_AFTER_MINT_RETURNS_DELTA_OFFSET : 0)
                | (permissions.afterBurnReturnsDelta ? 1 << HOOKS_AFTER_BURN_RETURNS_DELTA_OFFSET : 0)
        );
    }
}
