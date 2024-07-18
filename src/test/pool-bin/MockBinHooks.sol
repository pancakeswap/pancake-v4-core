// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Hooks} from "../../libraries/Hooks.sol";
import {IBinHooks} from "../../pool-bin/interfaces/IBinHooks.sol";
import {IBinPoolManager} from "../../pool-bin/interfaces/IBinPoolManager.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "../../types/PoolId.sol";

contract MockBinHooks is IBinHooks {
    using PoolIdLibrary for PoolKey;
    using Hooks for IBinHooks;

    bytes public beforeInitializeData;
    bytes public afterInitializeData;
    bytes public beforeMintData;
    bytes public afterMintData;
    bytes public beforeSwapData;
    bytes public afterSwapData;
    bytes public beforeBurnData;
    bytes public afterBurnData;
    bytes public beforeDonateData;
    bytes public afterDonateData;
    mapping(bytes4 => bytes4) public returnValues;
    mapping(PoolId => uint16) public swapFees;
    mapping(PoolId => uint16) public withdrawFees;
    uint16 bitmap;

    function setHooksRegistrationBitmap(uint16 _bitmap) external {
        bitmap = _bitmap;
    }

    function getHooksRegistrationBitmap() external view returns (uint16) {
        return bitmap;
    }

    function beforeInitialize(address, PoolKey calldata, uint24, bytes calldata hookData) external returns (bytes4) {
        beforeInitializeData = hookData;
        bytes4 selector = MockBinHooks.beforeInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterInitialize(address, PoolKey calldata, uint24, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        afterInitializeData = hookData;
        bytes4 selector = MockBinHooks.afterInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeMint(address, PoolKey calldata, IBinPoolManager.MintParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeMintData = hookData;
        bytes4 selector = MockBinHooks.beforeMint.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterMint(
        address,
        PoolKey calldata,
        IBinPoolManager.MintParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {
        afterMintData = hookData;
        bytes4 selector = MockBinHooks.afterMint.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeBurn(address, PoolKey calldata, IBinPoolManager.BurnParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeBurnData = hookData;
        bytes4 selector = MockBinHooks.beforeBurn.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterBurn(
        address,
        PoolKey calldata,
        IBinPoolManager.BurnParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {
        afterBurnData = hookData;
        bytes4 selector = MockBinHooks.afterBurn.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(address, PoolKey calldata, bool, int128, bytes calldata hookData)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapData = hookData;
        bytes4 selector = MockBinHooks.beforeSwap.selector;
        return (
            returnValues[selector] == bytes4(0) ? selector : returnValues[selector],
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function afterSwap(address, PoolKey calldata, bool, int128, BalanceDelta, bytes calldata hookData)
        external
        override
        returns (bytes4, int128)
    {
        afterSwapData = hookData;
        bytes4 selector = MockBinHooks.afterSwap.selector;
        return (returnValues[selector] == bytes4(0) ? selector : returnValues[selector], 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeDonateData = hookData;
        bytes4 selector = MockBinHooks.beforeDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        afterDonateData = hookData;
        bytes4 selector = MockBinHooks.afterDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }

    function setSwapFee(PoolKey calldata key, uint16 value) external {
        swapFees[key.toId()] = value;
    }
}
