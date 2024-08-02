// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IProtocolFees} from "../../../src/interfaces/IProtocolFees.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IHooks} from "../../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../../src/interfaces/IPoolManager.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {MockVault} from "../../../src/test/MockVault.sol";
import {MockBinDynamicFeeHook} from "../../../src/test/pool-bin/MockBinDynamicFeeHook.sol";
import {MockProtocolFeeController} from "../../../src/test/fee/MockProtocolFeeController.sol";
import {MockFeeManagerHook} from "../../../src/test/fee/MockFeeManagerHook.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../../../src/types/PoolId.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../../src/pool-bin/libraries/BinPool.sol";
import {PackedUint128Math} from "../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../../src/pool-bin/libraries/math/SafeCast.sol";
import {LiquidityConfigurations} from "../../../src/pool-bin/libraries/math/LiquidityConfigurations.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {BinPoolParametersHelper} from "../../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {LPFeeLibrary} from "../../../src/libraries/LPFeeLibrary.sol";
import {BinTestHelper} from "../helpers/BinTestHelper.sol";
import {BinFeeManagerHook} from "../helpers/BinFeeManagerHook.sol";
import {HOOKS_AFTER_INITIALIZE_OFFSET, HOOKS_BEFORE_MINT_OFFSET} from "../../../src/pool-bin/interfaces/IBinHooks.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {SortTokens} from "../../helpers/SortTokens.sol";

/**
 * @dev tests around fee for mint(), swap() and burn()
 */
contract BinPoolFeeTest is BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using BinPoolParametersHelper for bytes32;
    using SafeCast for uint256;

    MockVault public vault;
    BinPoolManager public poolManager;
    MockProtocolFeeController feeController;
    MockFeeManagerHook mockFeeManagerHook;
    BinFeeManagerHook binFeeManagerHook;

    PoolKey key;
    PoolId poolId;
    PoolKey key2;
    PoolId poolId2;
    bytes32 poolParam;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;
    Currency currency0;
    Currency currency1;
    Currency currency2;

    function setUp() public {
        vault = new MockVault();
        poolManager = new BinPoolManager(IVault(address(vault)), 500000);
        binFeeManagerHook = new BinFeeManagerHook(poolManager);

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        token2 = new MockERC20("TestC", "C", 18);

        (currency0, currency1, currency2) = SortTokens.sort(token0, token1, token2);

        poolParam = poolParam.setBinStep(10);
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: poolParam // binStep
        });
        poolId = key.toId();

        key2 = PoolKey({
            currency0: currency1,
            currency1: currency2,
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: poolParam // binStep
        });

        feeController = new MockProtocolFeeController();
        mockFeeManagerHook = new MockFeeManagerHook();
    }

    function test_MintCompositionFee_NoProtocolFee() external {
        uint24 binId = ID_ONE; // where token price are the same
        uint256 amountX = 1_000 * 1e18;
        uint256 amountY = 1_000 * 1e18;
        poolManager.initialize(key, binId, new bytes(0));

        // first mint: 5:5 ratio, will never incur composition fee for first mint
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 1e18, 1e18, "");

        // second mint:
        // 1. amt into bin [400e18, 500e18]
        // 2. user share: [434482758620689655172, 465517241379310344827]
        // 3. since user get more X, an internal swap from Y to X happened. thus fee on Y.
        //      -> fee: (500e18 - 465517241379310344827) * 0.3% ~ 0.1e18
        bytes32 expectedFee = uint128(0).encode(uint128(103758620689655172));
        bytes32 protocolFee = uint128(0).encode(uint128(0));
        bytes32 expectedAmtInBin = uint128(400e18).encode(uint128(500e18));
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory amounts = new bytes32[](1);
        ids[0] = binId;
        amounts[0] = expectedAmtInBin;
        vm.expectEmit();
        emit IBinPoolManager.Mint(key.toId(), bob, ids, 0, amounts, expectedFee, protocolFee);
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 4e17, 5e17, "");
    }

    /// @notice ensure that swapping always give more tokenOut compare to mint with implicit swap
    function testFuzz_SwapOutputMoreThanMint(uint24 lpFee, uint256 initialAmt) external {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.TEN_PERCENT_FEE));
        key.fee = lpFee;
        key2.fee = lpFee;

        // initialize both pool
        uint24 binId = ID_ONE; // where token price are the same
        poolManager.initialize(key, binId, new bytes(0));
        poolManager.initialize(key2, binId, new bytes(0));

        // add same liquidity (100 to 100_000 ether) to both pool
        initialAmt = uint256(bound(initialAmt, 100 ether, 100_000 ether));
        addLiquidityToBin(key, poolManager, alice, binId, initialAmt, initialAmt, 1e18, 1e18, "");
        addLiquidityToBin(key2, poolManager, alice, binId, initialAmt, initialAmt, 1e18, 1e18, "");

        // pool1: perform an implicit swap of tokenY for tokenX by adding 40 tokenX and 50 tokenY
        addLiquidityToBin(key, poolManager, bob, binId, 100 ether, 100 ether, 4e17, 5e17, "");
        uint256 shares = poolManager.getPosition(key.toId(), bob, binId, 0).share;
        BalanceDelta removeDela = removeLiquidityFromBin(key, poolManager, bob, binId, shares, "");
        uint128 tokenXOut = uint128(removeDela.amount0()) - 40 ether;
        uint128 tokenYIn = 50 ether - uint128(removeDela.amount1());

        // pool2: perform a swap. exactInput tokenY for tokenX
        BalanceDelta swapDelta = poolManager.swap(key, false, -int128(tokenYIn), "");

        // swap tokenOut >= mint with implicit swap
        assertGe(uint128(swapDelta.amount0()), tokenXOut);
    }

    function testFuzz_Mint_WithDynamicFeeTooLarge(uint24 swapFee) external {
        swapFee = uint24(bound(swapFee, LPFeeLibrary.TEN_PERCENT_FEE + 1, type(uint24).max));

        // 0000 0000 0000 0100, beforeMint
        uint16 bitMap = 0x0004;
        binFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(binFeeManagerHook)),
            poolManager: IPoolManager(address(poolManager)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(bitMap)).setBinStep(10)
        });

        uint24 activeId = ID_ONE; // where token price are the same
        poolManager.initialize(key, activeId, new bytes(0));

        bytes memory data = abi.encode(true, uint24(swapFee));
        vm.expectRevert(
            abi.encodeWithSelector(
                Hooks.FailedHookCall.selector,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, uint24(swapFee))
            )
        );
        addLiquidityToBin(key, poolManager, bob, activeId, 10_000 ether, 10_000 ether, 1e18, 1e18, data);
    }

    function test_Mint_WithDynamicFeeFromBeforeMintTooLarge() external {
        MockBinDynamicFeeHook hook = new MockBinDynamicFeeHook();
        hook.setLpFee(110_000); // 11% fee
        hook.setHooksRegistrationBitmap(uint16(1 << HOOKS_BEFORE_MINT_OFFSET));

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(hook)),
            poolManager: IPoolManager(address(poolManager)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: BinPoolParametersHelper.setBinStep(bytes32(uint256(hook.getHooksRegistrationBitmap())), 10)
        });

        uint24 binId = ID_ONE; // where token price are the same
        poolManager.initialize(key, binId, new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, 110_000));
        addLiquidityToBin(key, poolManager, bob, binId, 1000e18, 1000e18, 1e18, 1e18, "");
    }

    function test_MintCompositionFee_DynamicFee() external {
        mockFeeManagerHook.setHooksRegistrationBitmap(uint16(1 << HOOKS_AFTER_INITIALIZE_OFFSET));
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(mockFeeManagerHook)),
            poolManager: IPoolManager(address(poolManager)),
            /// @dev dynamic swap fee is 0 when pool is initialized, hence 0.3% will be ignored
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: BinPoolParametersHelper.setBinStep(
                bytes32(uint256(mockFeeManagerHook.getHooksRegistrationBitmap())), 10
            )
        });

        // this could be sync to pool through beforeInitialize hook
        mockFeeManagerHook.setSwapFee(6_000); // overwrite to 0.6% fee

        uint24 binId = ID_ONE; // where token price are the same
        uint256 amountX = 1_000 * 1e18;
        uint256 amountY = 1_000 * 1e18;
        poolManager.initialize(key, binId, new bytes(0));

        // first mint: 5:5 ratio, will never incur composition fee for first mint
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 1e18, 1e18, "");

        // second mint:
        // 1. amt into bin [400e18, 500e18]
        // 2. user share: [434482758620689655172, 465517241379310344827]
        // 3. since user get more X, an internal swap from Y to X happened. thus fee on Y.
        //      -> fee: (500e18 - 465517241379310344827) * 0.6% ~ 0.2e18
        bytes32 expectedFee = uint128(0).encode(uint128(208137931034482758));
        bytes32 protocolFee = uint128(0).encode(uint128(0));
        bytes32 expectedAmtInBin = uint128(400e18).encode(uint128(500e18));
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory amounts = new bytes32[](1);
        ids[0] = binId;
        amounts[0] = expectedAmtInBin;
        vm.expectEmit();
        emit IBinPoolManager.Mint(key.toId(), bob, ids, 0, amounts, expectedFee, protocolFee);
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 4e17, 5e17, "");
    }

    function test_MintCompositionFee_WithProtocolFee() external {
        // set protocolFee as 0.1% of fee
        uint24 pFee = _getSwapFee(1000, 1000);
        feeController.setProtocolFeeForPool(key, pFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        uint24 binId = ID_ONE; // where token price are the same
        uint256 amountX = 1_000 * 1e18;
        uint256 amountY = 1_000 * 1e18;
        poolManager.initialize(key, binId, new bytes(0));

        // first mint: 5:5 ratio, will never incur composition fee for first mint
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 1e18, 1e18, "");

        // protocol fee: 0.1% of fee
        // lp fee 0.3% * (1 - 0.1%) = 0.297% roughly 3 times of protocol fee
        // hence swap fee roughly 4 times of protocol fee
        bytes32 protocolFee = uint128(0).encode(uint128(34517241379310344));
        bytes32 expectedFee = uint128(0).encode(uint128(138378483068965517));
        bytes32 expectedAmtInBin = uint128(400e18).encode(uint128(500e18)).sub(protocolFee);
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory amounts = new bytes32[](1);
        ids[0] = binId;
        amounts[0] = expectedAmtInBin;
        vm.expectEmit();
        emit IBinPoolManager.Mint(key.toId(), bob, ids, 0, amounts, expectedFee, protocolFee);

        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 4e17, 5e17, "");

        assertEq(poolManager.protocolFeesAccrued(key.currency1), uint256(protocolFee.decodeY()));
    }

    function test_MintCompositionFee_WithDynamicFee() external {
        MockBinDynamicFeeHook hook = new MockBinDynamicFeeHook();
        hook.setLpFee(10_000); // 1%
        hook.setHooksRegistrationBitmap(uint16(1 << HOOKS_BEFORE_MINT_OFFSET));

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(hook)),
            poolManager: IPoolManager(address(poolManager)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: BinPoolParametersHelper.setBinStep(bytes32(uint256(hook.getHooksRegistrationBitmap())), 10)
        });

        uint24 binId = ID_ONE; // where token price are the same
        uint256 amountX = 1_000 * 1e18;
        uint256 amountY = 1_000 * 1e18;
        poolManager.initialize(key, binId, new bytes(0));

        // first mint: 1000e18 tokenX and 1000e18 tokenY with 5:5 ratio
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 1e18, 1e18, "");

        bytes32 protocolFee = uint128(0).encode(uint128(0));
        bytes32 expectedAmtInBin = uint128(1_000e10).encode(uint128(2_000e10));
        // as the current ratio is roughly 5:5, it means a swap of around 500e10 tokenY to tokenX
        bytes32 expectedFee = uint128(0).encode(uint128(50499999242)); // around 1% fee, ~5e10
        uint256[] memory ids = new uint256[](1);
        bytes32[] memory amounts = new bytes32[](1);
        ids[0] = binId;
        amounts[0] = expectedAmtInBin;
        vm.expectEmit();
        emit IBinPoolManager.Mint(key.toId(), bob, ids, 0, amounts, expectedFee, protocolFee);

        // second mint: 1000e10 tokenX and 2000e10 tokenY with 1:2 ratio
        addLiquidityToBin(key, poolManager, bob, binId, amountX, amountY, 1e10, 2e10, "");
    }

    function _addLiquidityForBurnTest(uint24 activeId, PoolKey memory _key) internal {
        uint256 amountX = 1000 ether;
        uint256 amountY = 1000 ether;
        poolManager.initialize(_key, activeId, new bytes(0));

        // mint 5:5 ratio
        addLiquidityToBin(_key, poolManager, bob, activeId, amountX, amountY, 1e18, 1e18, "");
    }

    function test_Burn_NoFee() external {
        // add liqudiity
        uint24 activeId = ID_ONE; // where token price are the same
        _addLiquidityForBurnTest(activeId, key);

        // then remove liquidity
        uint256[] memory balances = new uint256[](1);
        uint256[] memory ids = new uint256[](1);
        balances[0] = poolManager.getPosition(poolId, bob, activeId, 0).share;
        ids[0] = activeId;
        removeLiquidity(key, poolManager, bob, ids, balances);

        // check fee. no hook for pool, so can skip check
        assertEq(poolManager.protocolFeesAccrued(currency0), 0, "test_Burn_NoFee::1");
        assertEq(poolManager.protocolFeesAccrued(currency1), 0, "test_Burn_NoFee::1");
    }

    function test_Swap_NoFee() external {
        uint24 activeId = ID_ONE; // where token price are the same
        poolManager.initialize(key, activeId, new bytes(0));

        // addLiquidity: 10_000 token0 and token1 on active bin
        addLiquidityToBin(key, poolManager, bob, activeId, 10_000e18, 10_000e18, 1e18, 1e18, "");

        vm.startPrank(bob);
        vm.expectEmit();
        emit IBinPoolManager.Swap(key.toId(), bob, -1e18, (1e18 * 997) / 1000, activeId, 3000, 0);

        // swap: 1e18 X for Y. pool is 0.3% fee
        BalanceDelta delta = poolManager.swap(key, true, -int128(1e18), "0x");
        assertEq(delta.amount0(), -1e18, "test_Swap_NoFee::1");
        assertEq(delta.amount1(), (1e18 * 997) / 1000, "test_Swap_NoFee::2");

        // check fee. no hook for pool, so can skip check
        assertEq(poolManager.protocolFeesAccrued(currency0), 0, "test_Swap_NoFee::3");
        assertEq(poolManager.protocolFeesAccrued(currency1), 0, "test_Swap_NoFee::4");
    }

    function test_Swap_WithDynamicFee(uint24 poolFee) external {
        poolFee = uint24(bound(poolFee, 0, LPFeeLibrary.TEN_PERCENT_FEE - 1));

        // 0000 0000 0100 0000, beforeSwap
        uint16 bitMap = 0x0040;
        binFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(binFeeManagerHook)),
            poolManager: IPoolManager(address(poolManager)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            // parameters: poolParam // binStep
            parameters: bytes32(uint256(bitMap)).setBinStep(10)
        });

        // addLiquidity: 10_000 token0 and token1 on active bin
        uint24 activeId = ID_ONE; // where token price are the same
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 10_000 ether, 10_000 ether, 1e18, 1e18, "");

        // overwrite fee to 2%
        binFeeManagerHook.setFee(20_000);
        vm.prank(address(binFeeManagerHook));
        poolManager.updateDynamicLPFee(key, 20_000);

        // verify 2% fee instead of whatever fee set on the pool
        BalanceDelta delta = poolManager.swap(key, true, -int128(1e18), "");
        assertEq(delta.amount0(), -1e18, "test_Swap_WithDynamicFee::1");
        assertEq(delta.amount1(), (1e18 * 98) / 100, "test_Swap_WithDynamicFee::2");
    }

    function testFuzz_Swap_WithDynamicFeeTooLarge(uint24 swapFee) external {
        swapFee = uint24(bound(swapFee, LPFeeLibrary.TEN_PERCENT_FEE + 1, type(uint24).max));

        // 0000 0000 0100 0000, beforeSwap
        uint16 bitMap = 0x0040;
        binFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(binFeeManagerHook)),
            poolManager: IPoolManager(address(poolManager)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(bitMap)).setBinStep(10)
        });

        // addLiquidity: 10_000 token0 and token1 on active bin
        uint24 activeId = ID_ONE; // where token price are the same
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 10_000e18, 10_000e18, 1e18, 1e18, "");

        bytes memory data = abi.encode(true, uint24(swapFee));
        vm.expectRevert(
            abi.encodeWithSelector(
                Hooks.FailedHookCall.selector,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, uint24(swapFee))
            )
        );
        poolManager.swap(key, true, 1e18, data);
    }

    function _getSwapFee(uint24 fee0, uint24 fee1) internal pure returns (uint24) {
        return fee0 + (fee1 << 12);
    }

    /**
     * @dev given amountIn and fee (pool, protocol and hook level), calculate amount to lp and the feeAmt
     * @param feePercentage pool fee %, 10 imply 10%
     * @param protocolFeePercentage 10 imply 10%
     */
    function _getProtocolFeeForSwap(uint128 amtIn, uint128 feePercentage, uint128 protocolFeePercentage)
        internal
        pure
        returns (uint128 amtToLp, uint128 protocolFee)
    {
        uint128 totalFeeAmt = (amtIn * feePercentage) / 100;
        protocolFee = (totalFeeAmt * protocolFeePercentage) / 100;
        amtToLp = amtIn - protocolFee;
    }
}
