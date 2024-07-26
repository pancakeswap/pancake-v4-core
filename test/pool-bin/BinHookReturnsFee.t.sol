// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/Vault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {IProtocolFees} from "../../src/interfaces/IProtocolFees.sol";
import {IBinHooks} from "../../src/pool-bin/interfaces/IBinHooks.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {BinPoolManager} from "../../src/pool-bin/BinPoolManager.sol";
import {IBinPoolManager} from "../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BinDynamicReturnsFeeHook} from "./helpers/BinDynamicReturnsFeeHook.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "../../src/pool-cl/libraries/FullMath.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {BinLiquidityHelper} from "./helpers/BinLiquidityHelper.sol";
import {BinSwapHelper} from "./helpers/BinSwapHelper.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinHookReturnsFeeTest is Test, BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinDynamicReturnsFeeHook dynamicReturnsFeesHook;

    BinSwapHelper public binSwapHelper;
    BinLiquidityHelper public binLiquidityHelper;

    uint24 activeId = 2 ** 23; // where token0 and token1 price is the same

    PoolKey key;
    bytes32 poolParam;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

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
        vault = new Vault();
        poolManager = new BinPoolManager(IVault(address(vault)), 500000);
        vault.registerApp(address(poolManager));

        // initializeTokens
        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        dynamicReturnsFeesHook = new BinDynamicReturnsFeeHook();
        dynamicReturnsFeesHook.setManager(poolManager);

        binSwapHelper = new BinSwapHelper(poolManager, vault);
        binLiquidityHelper = new BinLiquidityHelper(poolManager, vault);
        token0.approve(address(binSwapHelper), 1000 ether);
        token1.approve(address(binSwapHelper), 1000 ether);
        token0.approve(address(binLiquidityHelper), 1000 ether);
        token1.approve(address(binLiquidityHelper), 1000 ether);

        token0.approve(address(dynamicReturnsFeesHook), 1000 ether);
        token1.approve(address(dynamicReturnsFeesHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: dynamicReturnsFeesHook,
            poolManager: poolManager,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())).setBinStep(10)
        });

        poolManager.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));
    }

    function test_fuzz_dynamicReturnSwapFee(uint24 fee) public {
        // hook will handle adding the override flag
        dynamicReturnsFeesHook.setFee(fee);

        uint24 actualFee = fee.removeOverrideFlag();

        int128 amountSpecified = -int128(10000);
        BalanceDelta result;
        if (actualFee > LPFeeLibrary.TEN_PERCENT_FEE) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, actualFee));
            result =
                binSwapHelper.swap(key, true, amountSpecified, BinSwapHelper.TestSettings(true, true), new bytes(0));
            return;
        } else {
            result =
                binSwapHelper.swap(key, true, amountSpecified, BinSwapHelper.TestSettings(true, true), new bytes(0));
        }

        uint128 amountSpecified128 = uint128(-amountSpecified);
        assertEq(-result.amount0(), int128(amountSpecified128));

        assertApproxEqAbs(
            uint256(int256(result.amount1())),
            FullMath.mulDiv(uint256(amountSpecified128), (1e6 - actualFee), 1e6),
            1 wei
        );
    }

    function test_dynamicReturnSwapFee_initializeZeroSwapFee() public {
        key.parameters =
            BinPoolParametersHelper.setBinStep(bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())), 1);
        poolManager.initialize(key, activeId, new bytes(0));
        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_notUsedIfPoolIsStaticFee() public {
        key.fee = 3000; // static fee
        dynamicReturnsFeesHook.setFee(1000); // 0.10% fee is NOT used because the pool has a static fee

        poolManager.initialize(key, activeId, new bytes(0));
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));
        assertEq(_fetchPoolSwapFee(key), 3000);

        // despite returning a valid swap fee (1000), the static fee is used
        int128 amountSpecified = -10000;
        BalanceDelta result;
        result = binSwapHelper.swap(key, true, amountSpecified, BinSwapHelper.TestSettings(true, true), new bytes(0));

        // after swapping ~1:1, the amount out (amount1) should be approximately 0.30% less than the amount specified
        uint128 amountSpecified128 = uint128(-amountSpecified);
        assertEq(-result.amount0(), int128(amountSpecified128));
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(amountSpecified128), (1e6 - 3000), 1e6), 1 wei
        );
    }

    function test_dynamicReturnSwapFee_notStored() public {
        // fees returned by beforeSwap are not written to storage

        // create a new pool with an initial fee of 123
        key.parameters =
            BinPoolParametersHelper.setBinStep(bytes32(uint256(dynamicReturnsFeesHook.getHooksRegistrationBitmap())), 1);
        poolManager.initialize(key, activeId, new bytes(0));
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        uint24 initialFee = 123;
        dynamicReturnsFeesHook.forcePoolFeeUpdate(key, initialFee);
        assertEq(_fetchPoolSwapFee(key), initialFee);

        // swap with a different fee
        uint24 newFee = 3000;
        dynamicReturnsFeesHook.setFee(newFee);

        int128 amountSpecified = -10000;
        BalanceDelta result =
            binSwapHelper.swap(key, true, amountSpecified, BinSwapHelper.TestSettings(true, true), new bytes(0));

        uint128 amountSpecified128 = uint128(-amountSpecified);
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(amountSpecified128), (1e6 - newFee), 1e6), 1 wei
        );

        // the fee from beforeSwap is not stored
        assertEq(_fetchPoolSwapFee(key), initialFee);
    }

    function test_dynamicReturnSwapFee_revertIfFeeTooLarge() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        // hook adds the override flag
        dynamicReturnsFeesHook.setFee(1000001);

        // a large fee is not used
        int128 amountSpecified = -10000;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, 1000001));
        binSwapHelper.swap(key, true, amountSpecified, BinSwapHelper.TestSettings(true, true), new bytes(0));
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,, swapFee) = poolManager.getSlot0(id);
    }
}
