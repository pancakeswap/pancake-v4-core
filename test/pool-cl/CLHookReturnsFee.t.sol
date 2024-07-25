// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {IProtocolFees} from "../../src/interfaces/IProtocolFees.sol";
import {ICLHooks} from "../../src/pool-cl/interfaces/ICLHooks.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {CLDynamicReturnsFeeHook} from "./helpers/CLDynamicReturnsFeeHook.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "../../src/pool-cl/libraries/FullMath.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CLHookReturnsFeeTest is Test, Deployers, TokenFixture, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    IVault vault;
    ICLPoolManager poolManager;
    CLDynamicReturnsFeeHook dynamicReturnsFeesHook;
    CLPoolManagerRouter router;

    PoolKey key;

    event Swap(
        PoolId indexed poolId,
        address sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    function setUp() public {
        dynamicReturnsFeesHook = new CLDynamicReturnsFeeHook();

        (vault, poolManager) = createFreshManager();
        dynamicReturnsFeesHook.setManager(poolManager);
        router = new CLPoolManagerRouter(vault, poolManager);

        initializeTokens();
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: dynamicReturnsFeesHook,
            poolManager: poolManager,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: CLPoolParametersHelper.setTickSpacing(
                bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())), 1
            )
        });

        poolManager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            ZERO_BYTES
        );
    }

    function test_fuzz_dynamicReturnSwapFee(uint24 fee) public {
        // hook will handle adding the override flag
        dynamicReturnsFeesHook.setFee(fee);

        uint24 actualFee = fee.removeOverrideFlag();

        int256 amountSpecified = -10000;
        BalanceDelta result;
        if (actualFee > LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, actualFee));
            result = router.swap(
                key,
                ICLPoolManager.SwapParams({
                    zeroForOne: true,
                    amountSpecified: amountSpecified,
                    sqrtPriceLimitX96: SQRT_RATIO_1_2
                }),
                CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
                ZERO_BYTES
            );
            return;
        } else {
            result = router.swap(
                key,
                ICLPoolManager.SwapParams({
                    zeroForOne: true,
                    amountSpecified: amountSpecified,
                    sqrtPriceLimitX96: SQRT_RATIO_1_2
                }),
                CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
                ZERO_BYTES
            );
        }
        assertEq(result.amount0(), amountSpecified);

        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - actualFee), 1e6), 1 wei
        );
    }

    function test_dynamicReturnSwapFee_initializeZeroSwapFee() public {
        key.parameters = CLPoolParametersHelper.setTickSpacing(
            bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())), 10
        );
        poolManager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_notUsedIfPoolIsStaticFee() public {
        key.fee = 3000; // static fee
        dynamicReturnsFeesHook.setFee(1000); // 0.10% fee is NOT used because the pool has a static fee

        poolManager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            ZERO_BYTES
        );

        assertEq(_fetchPoolSwapFee(key), 3000);

        // despite returning a valid swap fee (1000), the static fee is used
        int256 amountSpecified = -10000;
        BalanceDelta result = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: SQRT_RATIO_1_2
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ZERO_BYTES
        );

        // after swapping ~1:1, the amount out (amount1) should be approximately 0.30% less than the amount specified
        assertEq(result.amount0(), amountSpecified);
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - 3000), 1e6), 1 wei
        );
    }

    function test_dynamicReturnSwapFee_notStored() public {
        // fees returned by beforeSwap are not written to storage

        // create a new pool with an initial fee of 123
        key.parameters = CLPoolParametersHelper.setTickSpacing(
            bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())), 10
        );
        poolManager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 10000 ether, salt: 0}),
            ZERO_BYTES
        );
        uint24 initialFee = 123;
        dynamicReturnsFeesHook.forcePoolFeeUpdate(key, initialFee);
        assertEq(_fetchPoolSwapFee(key), initialFee);

        // swap with a different fee
        uint24 newFee = 3000;
        dynamicReturnsFeesHook.setFee(newFee);

        int256 amountSpecified = -10000;
        BalanceDelta result = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: SQRT_RATIO_1_2
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ZERO_BYTES
        );
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - newFee), 1e6), 1 wei
        );

        // the fee from beforeSwap is not stored
        assertEq(_fetchPoolSwapFee(key), initialFee);
    }

    function test_dynamicReturnSwapFee_revertIfFeeTooLarge() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        // hook adds the override flag
        dynamicReturnsFeesHook.setFee(1000001);

        // a large fee is not used
        int256 amountSpecified = 10000;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, 1000001));
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: SQRT_RATIO_1_2
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ZERO_BYTES
        );
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,,, swapFee) = poolManager.getSlot0(id);
    }
}
