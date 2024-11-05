// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {BaseBinTestHook} from "./BaseBinTestHook.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console2} from "forge-std/console2.sol";

contract BinReturnsDeltaHookOverwriteSwap is BaseBinTestHook {
    error InvalidAction();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    IBinPoolManager public immutable poolManager;
    PoolKey key;

    constructor(IVault _vault, IBinPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function setPoolKey(PoolKey memory _poolKey) external {
        key = _poolKey;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeMint: false,
                afterMint: false,
                beforeBurn: false,
                afterBurn: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: true,
                afterSwapReturnsDelta: false,
                afterMintReturnsDelta: false,
                afterBurnReturnsDelta: false
            })
        );
    }

    function addLiquidity(uint256 amt0, uint256 amt1) public {
        // do any logic

        // 1. Take input currency and amount from user
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amt0);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amt1);

        // 2. Mint -- so vault has token balance
        vault.lock(abi.encode(amt0, amt1));
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        (uint256 amt0, uint256 amt1) = abi.decode(callbackData, (uint256, uint256));

        vault.mint(address(this), key.currency0, amt0);
        key.currency0.settle(vault, address(this), amt0, false);

        vault.mint(address(this), key.currency1, amt1);
        key.currency1.settle(vault, address(this), amt1, false);
    }

    function beforeSwap(address, PoolKey calldata key, bool swapForY, int128 amountSpecified, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (Currency inputCurrency, Currency outputCurrency, uint256 amount) =
            _getInputOutputAndAmount(key, swapForY, amountSpecified);

        // 1. Take input currency and amount
        inputCurrency.take(vault, address(this), amount, true);

        // 2. Give output currency and amount achieving a 1:1 swap
        outputCurrency.settle(vault, address(this), amount, true);

        BeforeSwapDelta hookDelta = toBeforeSwapDelta(-amountSpecified, amountSpecified);
        return (this.beforeSwap.selector, hookDelta, 0);
    }

    /// @notice Get input, output currencies and amount from swap params
    function _getInputOutputAndAmount(PoolKey calldata key, bool swapForY, int128 amountSpecified)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = swapForY ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = amountSpecified < 0 ? uint128(-amountSpecified) : uint128(amountSpecified);
    }
}
