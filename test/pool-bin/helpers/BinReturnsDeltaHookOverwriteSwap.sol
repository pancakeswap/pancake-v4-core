// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {SafeCast} from "../../../src/libraries/SafeCast.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "../../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {BaseBinTestHook} from "./BaseBinTestHook.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {BinTestHelper} from "./BinTestHelper.sol";

import {console2} from "forge-std/console2.sol";

contract BinReturnsDeltaHookOverwriteSwap is BaseBinTestHook, BinTestHelper {
    using SafeCast for *;

    error InvalidAction();

    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    BinPoolManager public immutable poolManager;
    ActionType public actionType;
    PoolKey public key;

    uint24 activeId = 2 ** 23; // where token0 and token1 price is the same

    enum ActionType {
        Mint,
        Burn
    }

    struct BurnCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.BurnParams params;
        bytes hookData;
    }

    struct MintCallbackData {
        address sender;
        PoolKey key;
        IBinPoolManager.MintParams params;
        bytes hookData;
    }

    constructor(IVault _vault, IBinPoolManager _poolManager) {
        vault = _vault;
        poolManager = BinPoolManager(address(_poolManager));
    }

    function setPoolKey(PoolKey memory _poolKey) external {
        key = _poolKey;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeMint: false, // true eventually to block mint
                afterMint: false,
                beforeBurn: false, // true eventually to block mint
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
        // call binPoolManager to swap
        IBinPoolManager.MintParams memory params = _getSingleBinMintParams(activeId, amt0, amt1);

        MintCallbackData memory data = MintCallbackData(msg.sender, key, params, new bytes(0));
        actionType = ActionType.Mint;

        BalanceDelta delta = abi.decode(vault.lock(abi.encode(data)), (BalanceDelta));
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
        }

        if (delta.amount0() < 0) key.currency0.settle(vault, sender, uint128(-delta.amount0()), false);
        if (delta.amount0() > 0) key.currency0.take(vault, sender, uint128(delta.amount0()), false);
        if (delta.amount1() < 0) key.currency1.settle(vault, sender, uint128(-delta.amount1()), false);
        if (delta.amount1() > 0) key.currency1.take(vault, sender, uint128(delta.amount1()), false);

        return abi.encode(delta);
    }

    // user is -100, 100.
    function beforeSwap(address, PoolKey calldata key, bool swapForY, int128 amountSpecified, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (Currency inputCurrency, Currency outputCurrency, uint256 amount) =
            _getInputOutputAndAmount(key, swapForY, amountSpecified);

        // Step 1: remove all liquidity first
        IBinPoolManager.BurnParams memory burnParams =
            _getSingleBinBurnLiquidityParams(key, poolManager, activeId, address(this), 100);
        BalanceDelta delta = poolManager.burn(key, burnParams, new bytes(0));

        // Step 2: Add back remaining excess
        int256 delta0 = vault.currencyDelta(address(this), key.currency0);
        int256 delta1 = vault.currencyDelta(address(this), key.currency1);
        console2.log("before add delta");
        console2.logInt(delta0);
        console2.logInt(delta1);

        /// @dev delta is based on how much in and how much out accordingly to custom curve algorithm
        delta0 = delta0 + amount.toInt128();
        delta1 = delta1 - amount.toInt128();

        IBinPoolManager.MintParams memory mintParam =
            _getSingleBinMintParams(activeId, uint256(delta0), uint256(delta1));
        (delta,) = poolManager.mint(key, mintParam, new bytes(0));

        delta0 = vault.currencyDelta(address(this), key.currency0);
        delta1 = vault.currencyDelta(address(this), key.currency1);
        console2.log("after add delta");
        console2.logInt(delta0);
        console2.logInt(delta1);

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
