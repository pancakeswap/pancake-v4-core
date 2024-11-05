// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {IProtocolFees} from "../../src/interfaces/IProtocolFees.sol";
import {ICLHooks} from "../../src/pool-cl/interfaces/ICLHooks.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {FullMath} from "../../src/pool-cl/libraries/FullMath.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CLCustomCurveHook} from "./helpers/CLCustomCurveHook.sol";
import {CurrencySettlement} from "../helpers/CurrencySettlement.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";

contract CLHookCustomCurveTest is Test, Deployers, TokenFixture, GasSnapshot {
    using SafeCast for *;
    using CurrencySettlement for Currency;

    IVault vault;
    ICLPoolManager poolManager;
    CLCustomCurveHook hook;
    CLPoolManagerRouter router;
    PoolKey key;

    function setUp() public {
        (vault, poolManager) = createFreshManager();
        hook = new CLCustomCurveHook(vault, poolManager);
        router = new CLPoolManagerRouter(vault, poolManager);

        initializeTokens();
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: 3000,
            parameters: CLPoolParametersHelper.setTickSpacing(bytes32(uint256(hook.getHooksRegistrationBitmap())), 10)
        });

        // make sure hook has enough balance to initialize the pool
        currency0.transfer(address(hook), 1);
        currency1.transfer(address(hook), 1);

        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function test_modifyLiquidity(uint256 addAmt0, uint256 addAmt1, uint256 rmAmt0, uint256 rmAmt1) public {
        addAmt0 = bound(addAmt1, 0, 999 ether);
        addAmt1 = bound(addAmt1, 0, 999 ether);

        // 0. transfer tokens to hook
        currency0.transfer(address(hook), addAmt0);
        currency1.transfer(address(hook), addAmt1);

        // 1. user add arbitrary amount of liquidity
        hook.addLiquidity(key, addAmt0, addAmt0);

        // contract level checks
        assertEq(currency0.balanceOf(address(vault)), addAmt0 + 1);
        assertEq(currency1.balanceOf(address(vault)), addAmt1 + 1);

        // app level checks
        assertEq(vault.reservesOfApp(address(poolManager), currency0), addAmt0 + 1);
        assertEq(vault.reservesOfApp(address(poolManager), currency1), addAmt1 + 1);

        // 2. user remove arbitrary amount of liquidity
        if (rmAmt0 > addAmt0 || rmAmt1 > addAmt1) {
            vm.expectRevert();
            hook.removeLiquidity(key, rmAmt0, rmAmt1, makeAddr("recipient"));
        } else {
            hook.removeLiquidity(key, rmAmt0, rmAmt1, makeAddr("recipient"));

            // contract level checks
            assertEq(currency0.balanceOf(address(vault)), addAmt0 - rmAmt0 + 1);
            assertEq(currency1.balanceOf(address(vault)), addAmt1 - rmAmt1 + 1);

            // app level checks
            assertEq(vault.reservesOfApp(address(poolManager), currency0), addAmt0 - rmAmt0 + 1);
            assertEq(vault.reservesOfApp(address(poolManager), currency1), addAmt1 - rmAmt1 + 1);

            // check recipient balance
            assertEq(currency0.balanceOf(makeAddr("recipient")), rmAmt0);
            assertEq(currency1.balanceOf(makeAddr("recipient")), rmAmt1);
        }
    }

    function test_swap(uint256 swapRatio, bool zeroForOne, int256 amountSpecified) public {
        /// @dev swap ratio is the amount of output token to get given amount of input token
        /// outputAmt = inputTOken * swapRatio / 1000000
        swapRatio = bound(swapRatio, 0, 1000000);

        amountSpecified = bound(amountSpecified, 1, 100 ether);

        // 0. let's say the pool starts with 100 ether of each token
        currency0.transfer(address(hook), 100 ether);
        currency1.transfer(address(hook), 100 ether);
        hook.addLiquidity(key, 100 ether, 100 ether);

        vault.lock(abi.encodeCall(CLHookCustomCurveTest._test_swap, (swapRatio, zeroForOne, amountSpecified)));
    }

    function _test_swap(uint256 swapRatio, bool zeroForOne, int256 amountSpecified) external {
        // 1. swap
        /// @dev reuse poolManager interface to swap
        poolManager.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1
            }),
            abi.encode(swapRatio)
        );

        uint256 inputAmt = amountSpecified.toUint256();
        uint256 outputAmt = inputAmt * swapRatio / 1000000;

        // 2. finish payment
        if (zeroForOne) {
            currency0.settle(vault, address(this), inputAmt, false);
            currency1.take(vault, makeAddr("recipient"), outputAmt, false);
        } else {
            currency1.settle(vault, address(this), inputAmt, false);
            currency0.take(vault, makeAddr("recipient"), outputAmt, false);
        }

        // 3. check balances

        // contract level checks
        if (zeroForOne) {
            assertEq(currency0.balanceOf(address(vault)), 100 ether + inputAmt + 1);
            assertEq(currency1.balanceOf(address(vault)), 100 ether - outputAmt + 1);
        } else {
            assertEq(currency0.balanceOf(address(vault)), 100 ether - outputAmt + 1);
            assertEq(currency1.balanceOf(address(vault)), 100 ether + inputAmt + 1);
        }

        // app level checks
        if (zeroForOne) {
            assertEq(vault.reservesOfApp(address(poolManager), currency0), 100 ether + inputAmt + 1);
            assertEq(vault.reservesOfApp(address(poolManager), currency1), 100 ether - outputAmt + 1);
        } else {
            assertEq(vault.reservesOfApp(address(poolManager), currency0), 100 ether - outputAmt + 1);
            assertEq(vault.reservesOfApp(address(poolManager), currency1), 100 ether + inputAmt + 1);
        }

        // check recipient balance
        if (zeroForOne) {
            assertEq(currency1.balanceOf(makeAddr("recipient")), outputAmt);
        } else {
            assertEq(currency0.balanceOf(makeAddr("recipient")), outputAmt);
        }
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory result) {
        // forward the call and bubble up the error if revert
        bool success;
        (success, result) = address(this).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }
}
