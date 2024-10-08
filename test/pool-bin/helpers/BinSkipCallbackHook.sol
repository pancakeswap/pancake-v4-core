// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Currency, CurrencyLibrary} from "../../../src/types/Currency.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";
import {IBinHooks} from "../../../src/pool-bin/interfaces/IBinHooks.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {BaseBinTestHook} from "./BaseBinTestHook.sol";

/// @notice CL hook which does a callback
contract BinSkipCallbackHook is BaseBinTestHook {
    error InvalidAction();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IBinPoolManager public immutable poolManager;
    IVault public immutable vault;
    ActionType public actionType;

    enum ActionType {
        Mint,
        Burn,
        Swap,
        Donate
    }

    uint16 bitmap;
    uint256 public hookCounterCallbackCount;

    constructor(IVault _vault, IBinPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeMint: true,
                afterMint: true,
                beforeBurn: true,
                afterBurn: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true,
                beforeSwapReturnsDelta: true,
                afterSwapReturnsDelta: true,
                afterMintReturnsDelta: true,
                afterBurnReturnsDelta: true
            })
        );
    }

    struct CallbackData {
        bytes action;
        bytes rawCallbackData;
    }

    struct BurnCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.BurnParams params;
        bytes hookData;
    }

    function burn(PoolKey memory key, IBinPoolManager.BurnParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        BurnCallbackData memory data = BurnCallbackData(msg.sender, key, params, hookData);
        actionType = ActionType.Burn;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));
    }

    struct MintCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.MintParams params;
        bytes hookData;
    }

    function mint(PoolKey memory key, IBinPoolManager.MintParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        MintCallbackData memory data = MintCallbackData(msg.sender, key, params, hookData);
        actionType = ActionType.Mint;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));
    }

    struct SwapCallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        bool swapForY;
        uint128 amountIn;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    function swap(
        PoolKey memory key,
        bool swapForY,
        uint128 amountIn,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        SwapCallbackData memory data = SwapCallbackData(msg.sender, testSettings, key, swapForY, amountIn, hookData);
        actionType = ActionType.Swap;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    struct DonateCallbackData {
        address sender;
        PoolKey key;
        uint128 amount0;
        uint128 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        DonateCallbackData memory data = DonateCallbackData(msg.sender, key, amount0, amount1, hookData);
        actionType = ActionType.Donate;

        delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        require(msg.sender == address(vault));
        BalanceDelta delta;
        PoolKey memory key;
        address sender;

        if (actionType == ActionType.Burn) {
            BurnCallbackData memory data = abi.decode(callbackData, (BurnCallbackData));

            key = data.key;
            sender = data.sender;
            delta = poolManager.burn(data.key, data.params, data.hookData);
        } else if (actionType == ActionType.Mint) {
            MintCallbackData memory data = abi.decode(callbackData, (MintCallbackData));

            key = data.key;
            sender = data.sender;
            (delta,) = poolManager.mint(data.key, data.params, data.hookData);
        } else if (actionType == ActionType.Swap) {
            SwapCallbackData memory data = abi.decode(callbackData, (SwapCallbackData));

            key = data.key;
            sender = data.sender;
            delta = poolManager.swap(data.key, data.swapForY, -int128(data.amountIn), data.hookData);
        } else if (actionType == ActionType.Donate) {
            DonateCallbackData memory data = abi.decode(callbackData, (DonateCallbackData));

            key = data.key;
            sender = data.sender;
            (delta,) = poolManager.donate(data.key, data.amount0, data.amount1, data.hookData);
        }

        if (delta.amount0() < 0) key.currency0.settle(vault, sender, uint128(-delta.amount0()), false);
        if (delta.amount0() > 0) key.currency0.take(vault, sender, uint128(delta.amount0()), false);
        if (delta.amount1() < 0) key.currency1.settle(vault, sender, uint128(-delta.amount1()), false);
        if (delta.amount1() > 0) key.currency1.take(vault, sender, uint128(delta.amount1()), false);

        return abi.encode(delta);
    }

    function initialize(PoolKey memory key, uint24 activeId) external {
        poolManager.initialize(key, activeId);
    }

    function beforeInitialize(address, PoolKey calldata, uint24) external override returns (bytes4) {
        hookCounterCallbackCount++;
        return BinSkipCallbackHook.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint24) external override returns (bytes4) {
        hookCounterCallbackCount++;
        return BinSkipCallbackHook.afterInitialize.selector;
    }

    function beforeMint(address, PoolKey calldata, IBinPoolManager.MintParams calldata, bytes calldata)
        external
        override
        returns (bytes4, uint24)
    {
        hookCounterCallbackCount++;
        return (BinSkipCallbackHook.beforeMint.selector, 0);
    }

    function afterMint(address, PoolKey calldata, IBinPoolManager.MintParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, BalanceDelta)
    {
        hookCounterCallbackCount++;
        return (BinSkipCallbackHook.afterMint.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeBurn(address, PoolKey calldata, IBinPoolManager.BurnParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return BinSkipCallbackHook.beforeBurn.selector;
    }

    function afterBurn(address, PoolKey calldata, IBinPoolManager.BurnParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, BalanceDelta)
    {
        hookCounterCallbackCount++;
        return (BinSkipCallbackHook.afterBurn.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(address, PoolKey calldata, bool, int128, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        hookCounterCallbackCount++;
        return (BinSkipCallbackHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, bool, int128, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        hookCounterCallbackCount++;
        return (BinSkipCallbackHook.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return BinSkipCallbackHook.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return BinSkipCallbackHook.afterDonate.selector;
    }
}
