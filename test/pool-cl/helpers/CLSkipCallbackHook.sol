// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../../../src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";

/// @notice CL hook which does a callback
contract CLSkipCallbackHook is BaseCLTestHook {
    error InvalidAction();

    using CurrencyLibrary for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;

    uint16 bitmap;
    uint256 public hookCounterCallbackCount;

    constructor(IVault _vault, ICLPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true,
                befreSwapReturnsDelta: true,
                afterSwapReturnsDelta: true,
                afterAddLiquidityReturnsDelta: true,
                afterRemoveLiquidityReturnsDelta: true
            })
        );
    }

    struct CallbackData {
        bytes action;
        bytes rawCallbackData;
    }

    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes memory hookData) external {
        poolManager.initialize(key, sqrtPriceX96, hookData);
    }

    struct ModifyPositionCallbackData {
        address sender;
        PoolKey key;
        ICLPoolManager.ModifyLiquidityParams params;
        bytes hookData;
    }

    function modifyPosition(
        PoolKey memory key,
        ICLPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            vault.lock(
                abi.encode("modifyPosition", abi.encode(ModifyPositionCallbackData(msg.sender, key, params, hookData)))
            ),
            (BalanceDelta)
        );

        // if any ethers left
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function modifyPositionCallback(bytes memory rawData) private returns (bytes memory) {
        ModifyPositionCallbackData memory data = abi.decode(rawData, (ModifyPositionCallbackData));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(data.key, data.params, data.hookData);

        if (delta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                vault.settle{value: uint128(delta.amount0())}(data.key.currency0);
            } else {
                vault.sync(data.key.currency0);
                IERC20(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(vault), uint128(delta.amount0())
                );
                vault.settle(data.key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (data.key.currency1.isNative()) {
                vault.settle{value: uint128(delta.amount1())}(data.key.currency1);
            } else {
                vault.sync(data.key.currency1);
                IERC20(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(vault), uint128(delta.amount1())
                );
                vault.settle(data.key.currency1);
            }
        }

        if (delta.amount0() < 0) {
            vault.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
        }
        if (delta.amount1() < 0) {
            vault.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
        }

        return abi.encode(delta);
    }

    struct SwapTestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    struct SwapCallbackData {
        address sender;
        SwapTestSettings testSettings;
        PoolKey key;
        ICLPoolManager.SwapParams params;
        bytes hookData;
    }

    function swap(
        PoolKey memory key,
        ICLPoolManager.SwapParams memory params,
        SwapTestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            vault.lock(
                abi.encode("swap", abi.encode(SwapCallbackData(msg.sender, testSettings, key, params, hookData)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function swapCallback(bytes memory rawData) private returns (bytes memory) {
        SwapCallbackData memory data = abi.decode(rawData, (SwapCallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);
        if (data.params.zeroForOne) {
            if (delta.amount0() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency0.isNative()) {
                        vault.settle{value: uint128(delta.amount0())}(data.key.currency0);
                    } else {
                        vault.sync(data.key.currency0);
                        IERC20(Currency.unwrap(data.key.currency0)).transferFrom(
                            data.sender, address(vault), uint128(delta.amount0())
                        );
                        vault.settle(data.key.currency0);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    vault.transferFrom(data.sender, address(this), data.key.currency0, uint128(delta.amount0()));
                    vault.burn(address(this), data.key.currency0, uint128(delta.amount0()));
                }
            }
            if (delta.amount1() < 0) {
                if (data.testSettings.withdrawTokens) {
                    vault.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
                } else {
                    vault.mint(data.sender, data.key.currency1, uint128(-delta.amount1()));
                }
            }
        } else {
            if (delta.amount1() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency1.isNative()) {
                        vault.settle{value: uint128(delta.amount1())}(data.key.currency1);
                    } else {
                        vault.sync(data.key.currency1);
                        IERC20(Currency.unwrap(data.key.currency1)).transferFrom(
                            data.sender, address(vault), uint128(delta.amount1())
                        );
                        vault.settle(data.key.currency1);
                    }
                } else {
                    // the received hook on this transfer will burn the tokens
                    vault.transferFrom(data.sender, address(this), data.key.currency1, uint128(delta.amount1()));
                    vault.burn(address(this), data.key.currency1, uint128(delta.amount1()));
                }
            }
            if (delta.amount0() < 0) {
                if (data.testSettings.withdrawTokens) {
                    vault.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
                } else {
                    vault.mint(data.sender, data.key.currency0, uint128(-delta.amount0()));
                }
            }
        }

        return abi.encode(delta);
    }

    struct DonateCallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            vault.lock(
                abi.encode("donate", abi.encode(DonateCallbackData(msg.sender, key, amount0, amount1, hookData)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function donateCallback(bytes memory rawData) private returns (bytes memory) {
        DonateCallbackData memory data = abi.decode(rawData, (DonateCallbackData));

        BalanceDelta delta = poolManager.donate(data.key, data.amount0, data.amount1, data.hookData);
        if (delta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                vault.settle{value: uint128(delta.amount0())}(data.key.currency0);
            } else {
                vault.sync(data.key.currency0);
                IERC20(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(vault), uint128(delta.amount0())
                );
                vault.settle(data.key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (data.key.currency1.isNative()) {
                vault.settle{value: uint128(delta.amount1())}(data.key.currency1);
            } else {
                vault.sync(data.key.currency1);
                IERC20(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(vault), uint128(delta.amount1())
                );
                vault.settle(data.key.currency1);
            }
        }

        return abi.encode(delta);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (bytes memory action, bytes memory rawCallbackData) = abi.decode(data, (bytes, bytes));

        if (keccak256(action) == keccak256("modifyPosition")) {
            return modifyPositionCallback(rawCallbackData);
        } else if (keccak256(action) == keccak256("swap")) {
            return swapCallback(rawCallbackData);
        } else if (keccak256(action) == keccak256("donate")) {
            return donateCallback(rawCallbackData);
        } else {
            revert InvalidAction();
        }
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external override returns (bytes4) {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        hookCounterCallbackCount++;
        return (CLSkipCallbackHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        hookCounterCallbackCount++;
        return (CLSkipCallbackHook.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(address, PoolKey calldata, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        hookCounterCallbackCount++;
        return (CLSkipCallbackHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, ICLPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        hookCounterCallbackCount++;
        return (CLSkipCallbackHook.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        hookCounterCallbackCount++;
        return CLSkipCallbackHook.afterDonate.selector;
    }
}
