// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {ICLHooks} from "../../../src/pool-cl/interfaces/ICLHooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "../../../src/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {SafeCast} from "../../../src/libraries/SafeCast.sol";
import {Constants} from "./Constants.sol";
import {CLPoolParametersHelper} from "../../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {console2} from "forge-std/console2.sol";

contract CLCustomCurveHook is BaseCLTestHook {
    using CLPoolParametersHelper for bytes32;
    using SafeCast for *;
    using CurrencySettlement for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    IVault public immutable vault;
    ICLPoolManager public immutable manager;

    constructor(IVault _vault, ICLPoolManager _manager) {
        vault = _vault;
        manager = _manager;
    }

    // *****  Custom Curve Interface  *****//

    function addLiquidity(PoolKey calldata key, uint256 amount0, uint256 amount1) public {
        // 1. custom curve minting position token logic

        // 2. deposit token into vault
        vault.lock(abi.encode("deposit", abi.encode(key, amount0, amount1)));
    }

    function removeLiquidity(PoolKey calldata key, uint256 amount0, uint256 amount1, address recipient) public {
        // 1. custom curve burning position token logic

        // 2. withdraw token from vault
        vault.lock(abi.encode("withdraw", abi.encode(key, amount0, amount1, recipient)));
    }

    // *****  ICLHooks Interface  *****//

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                afterInitialize: true,
                beforeAddLiquidity: true,
                beforeSwap: true,
                befreSwapReturnsDelta: true,
                // disable all other hooks
                beforeInitialize: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        override
        returns (bytes4)
    {
        require(sqrtPriceX96 == Constants.SQRT_RATIO_1_1, "InvalidSqrtPrice");
        require(tick == 0, "InvalidTick");
        require(key.parameters.getTickSpacing() == 10, "InvalidTickSpacing");

        vault.lock(abi.encode("init", abi.encode(key)));

        return ICLHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        revert("banned adding liquidity by non-hook");
    }

    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external override returns (bytes4) {
        revert("banned donating by non-hook");
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        ICLPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 swapRatio = abi.decode(hookData, (uint256));

        // to simplify the test, amountSpecified is always negative hence always indicates input token amount
        int256 amountUnSpecified = -params.amountSpecified * int256(swapRatio) / 1000000;
        BeforeSwapDelta beforeSwapDelta =
            toBeforeSwapDelta((-params.amountSpecified).toInt128(), -amountUnSpecified.toInt128());

        console2.log("zeroForOne: ", params.zeroForOne);
        console2.log("amoutSpecified: ", beforeSwapDelta.getSpecifiedDelta());
        console2.log("amoutUnSpecified: ", beforeSwapDelta.getUnspecifiedDelta());

        if (params.zeroForOne) {
            // input token is token0, amt = amountSpecified, deposit it to vault
            key.currency0.take(vault, address(this), (-params.amountSpecified).toUint256(), false);
            _dispatch(abi.encode("deposit", abi.encode(key, (-params.amountSpecified).toUint256(), 0)));

            // output token is token1, amt = amountUnSpecified, withdraw it from vault
            _dispatch(abi.encode("withdraw", abi.encode(key, 0, amountUnSpecified, address(this))));
            key.currency1.settle(vault, address(this), amountUnSpecified.toUint256(), false);
        } else {
            // input token is token1, amt = amountSpecified, deposit it to vault
            key.currency1.take(vault, address(this), (-params.amountSpecified).toUint256(), false);
            _dispatch(abi.encode("deposit", abi.encode(key, 0, (-params.amountSpecified).toUint256())));

            // output token is token0, amt = amountUnSpecified, withdraw it from vault
            _dispatch(abi.encode("withdraw", abi.encode(key, amountUnSpecified, 0, address(this))));
            key.currency0.settle(vault, address(this), amountUnSpecified.toUint256(), false);
        }

        console2.log("hook balanceDelta0:", vault.currencyDelta(address(this), key.currency0));
        console2.log("hook balanceDelta1:", vault.currencyDelta(address(this), key.currency1));

        return (ICLHooks.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function lockAcquired(bytes memory data) external returns (bytes memory) {
        require(msg.sender == address(vault));
        return _dispatch(data);
    }

    function _dispatch(bytes memory data) internal returns (bytes memory) {
        (bytes memory action, bytes memory rawCallbackData) = abi.decode(data, (bytes, bytes));

        if (keccak256(action) == keccak256("init")) {
            (PoolKey memory key) = abi.decode(rawCallbackData, (PoolKey));

            /// @dev expected to be called when pool is initialized
            /// this could mint a tiny liquidity position to the hook
            /// so that all the donated tokens are actually received by the hook
            /// we make use of it to manage the custom curve's fund
            manager.modifyLiquidity(
                key,
                ICLPoolManager.ModifyLiquidityParams({
                    tickLower: -10,
                    tickUpper: 10,
                    liquidityDelta: 1,
                    salt: bytes32(0)
                }),
                ""
            );

            key.currency0.settle(vault, address(this), 1, false);
            key.currency1.settle(vault, address(this), 1, false);
        } else if (keccak256(action) == keccak256("deposit")) {
            /// @dev expected to be called when user add liquidity
            /// deposit token through donate
            /// this could effectively increase the reservesOfApp
            /// hence avoid the empty fund issue

            (PoolKey memory key, uint256 amount0, uint256 amount1) =
                abi.decode(rawCallbackData, (PoolKey, uint256, uint256));

            manager.donate(key, amount0, amount1, "");

            if (amount0 > 0) {
                key.currency0.settle(vault, address(this), amount0, false);
            }
            if (amount1 > 0) {
                key.currency1.settle(vault, address(this), amount1, false);
            }
        } else if (keccak256(action) == keccak256("withdraw")) {
            /// @dev expected to be called when user remove liquidity
            /// withdraw token through modifyLiquidity (token stored as fee)
            /// this could effectively decrease the reservesOfApp
            /// hence avoid affecting the reserves of other pools

            (PoolKey memory key, uint256 amount0, uint256 amount1, address recipient) =
                abi.decode(rawCallbackData, (PoolKey, uint256, uint256, address));

            (, BalanceDelta feeDelta) = manager.modifyLiquidity(
                key,
                ICLPoolManager.ModifyLiquidityParams({
                    tickLower: -10,
                    tickUpper: 10,
                    liquidityDelta: 0,
                    salt: bytes32(0)
                }),
                ""
            );

            uint256 balance0 = feeDelta.amount0().toUint256() - amount0;
            uint256 balance1 = feeDelta.amount1().toUint256() - amount1;

            // deposit the remaining balance back
            if (balance0 > 0 || balance1 > 0) {
                manager.donate(key, balance0, balance1, "");
            }

            // transfer the removed liquidity to recipient
            if (amount0 > 0) {
                key.currency0.take(vault, recipient, amount0, false);
            }
            if (amount1 > 0) {
                key.currency1.take(vault, recipient, amount1, false);
            }
        } else {
            revert("InvalidAction");
        }
    }
}
