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

contract BinCustomCurveHook is BaseBinTestHook {
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

    /// @dev assume user call hook to add liquidity
    function addLiquidity(uint256 amt0, uint256 amt1) public {
        // 1. Take input currency and amount from user
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amt0);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amt1);

        // 2. Mint -- so vault has token balance
        vault.lock(abi.encode("mint", abi.encode(amt0, amt1)));
    }

    /// @dev assume user call hook to remove liquidity
    function removeLiquidity(uint256 amt0, uint256 amt1) public {
        // 2. Mint -- so vault has token balance
        vault.lock(abi.encode("burn", abi.encode(amt0, amt1)));

        IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, amt0);
        IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, amt1);
    }

    function lockAcquired(bytes calldata callbackData) external returns (bytes memory) {
        (bytes memory action, bytes memory rawCallbackData) = abi.decode(callbackData, (bytes, bytes));

        if (keccak256(action) == keccak256("mint")) {
            (uint256 amt0, uint256 amt1) = abi.decode(rawCallbackData, (uint256, uint256));

            // transfer token to the vault and mint VaultToken
            key.currency0.settle(vault, address(this), amt0, false);
            key.currency0.take(vault, address(this), amt0, true);

            key.currency1.settle(vault, address(this), amt1, false);
            key.currency1.take(vault, address(this), amt1, true);
        } else if (keccak256(action) == keccak256("burn")) {
            (uint256 amt0, uint256 amt1) = abi.decode(rawCallbackData, (uint256, uint256));

            // take token from the vault and burn VaultToken
            key.currency0.take(vault, address(this), amt0, false);
            key.currency0.settle(vault, address(this), amt0, true);

            key.currency1.take(vault, address(this), amt1, false);
            key.currency1.settle(vault, address(this), amt1, true);
        }
    }

    /// @dev 1:1 swap
    function beforeSwap(address, PoolKey calldata key, bool swapForY, int128 amountSpecified, bytes calldata)
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
    function _getInputOutputAndAmount(PoolKey calldata _key, bool swapForY, int128 amountSpecified)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = swapForY ? (_key.currency0, _key.currency1) : (_key.currency1, _key.currency0);

        amount = amountSpecified < 0 ? uint128(-amountSpecified) : uint128(amountSpecified);
    }
}
