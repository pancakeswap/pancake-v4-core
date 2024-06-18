// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IBinPoolManager} from "../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {Vault} from "../../src/Vault.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../src/types/BalanceDelta.sol";
import {BinPoolManager} from "../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../src/pool-bin/libraries/BinPool.sol";
import {PackedUint128Math} from "../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../src/pool-bin/libraries/math/SafeCast.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {Constants} from "../../src/pool-bin/libraries/Constants.sol";
import {IBinHooks} from "../../src/pool-bin/interfaces/IBinHooks.sol";
import {BinFeeManagerHook} from "./helpers/BinFeeManagerHook.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IBinHooks} from "../../src/pool-bin/interfaces/IBinHooks.sol";
import {BinSwapHelper} from "./helpers/BinSwapHelper.sol";
import {BinLiquidityHelper} from "./helpers/BinLiquidityHelper.sol";
import {BinDonateHelper} from "./helpers/BinDonateHelper.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {BinReturnsDeltaHook} from "./helpers/BinReturnsDeltaHook.sol";

contract BinHookReturnsDelta is Test, GasSnapshot, BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinReturnsDeltaHook public binReturnsDeltaHook;

    BinSwapHelper public binSwapHelper;
    BinLiquidityHelper public binLiquidityHelper;
    BinDonateHelper public binDonateHelper;

    uint24 activeId = 2 ** 23; // where token0 and token1 price is the same

    PoolKey key;
    bytes32 poolParam;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        vault = new Vault();
        poolManager = new BinPoolManager(IVault(address(vault)), 500000);

        vault.registerApp(address(poolManager));

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        IBinPoolManager iBinPoolManager = IBinPoolManager(address(poolManager));
        IVault iVault = IVault(address(vault));

        binSwapHelper = new BinSwapHelper(iBinPoolManager, iVault);
        binLiquidityHelper = new BinLiquidityHelper(iBinPoolManager, iVault);
        binDonateHelper = new BinDonateHelper(iBinPoolManager, iVault);
        token0.approve(address(binSwapHelper), 1000 ether);
        token1.approve(address(binSwapHelper), 1000 ether);
        token0.approve(address(binLiquidityHelper), 1000 ether);
        token1.approve(address(binLiquidityHelper), 1000 ether);
        token0.approve(address(binDonateHelper), 1000 ether);
        token1.approve(address(binDonateHelper), 1000 ether);

        binReturnsDeltaHook = new BinReturnsDeltaHook(iVault, iBinPoolManager);
        token0.approve(address(binReturnsDeltaHook), 1000 ether);
        token1.approve(address(binReturnsDeltaHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: binReturnsDeltaHook,
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(binReturnsDeltaHook.getHooksRegistrationBitmap())).setBinStep(10)
        });

        poolManager.initialize(key, activeId, new bytes(0));
    }

    function testMint_MintMore() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        BalanceDelta delta = binLiquidityHelper.mint(key, mintParams, abi.encode(0));
        (uint128 reserveXBefore, uint128 reserveYBefore) = poolManager.getBin(key.toId(), activeId);

        BalanceDelta delta2 = binLiquidityHelper.mint(key, mintParams, abi.encode(mintParams.amountIn));
        (uint128 reserveXAfter, uint128 reserveYAfter) = poolManager.getBin(key.toId(), activeId);

        assertEq(reserveXAfter - reserveXBefore, 2 * reserveXBefore);
        assertEq(reserveYAfter - reserveYBefore, 2 * reserveYBefore);

        assertEq(delta.amount0() * 2, delta2.amount0());
        assertEq(delta.amount1() * 2, delta2.amount1());
    }

    function testBurn_FeeCharge() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        (uint128 reserveXBefore, uint128 reserveYBefore) = poolManager.getBin(key.toId(), activeId);

        assertEq(reserveXBefore, 1 ether);
        assertEq(reserveYBefore, 1 ether);
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 0);
        assertEq(token1.balanceOf(address(binReturnsDeltaHook)), 0);

        IBinPoolManager.BurnParams memory burnParams =
            _getSingleBinBurnLiquidityParams(key, poolManager, activeId, address(binLiquidityHelper), 100);

        binLiquidityHelper.burn(key, burnParams, "");

        (uint128 reserveXAfter, uint128 reserveYAfter) = poolManager.getBin(key.toId(), activeId);

        assertEq(reserveXAfter, 0);
        assertEq(reserveYAfter, 0);
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 0.1 ether);
        assertEq(token1.balanceOf(address(binReturnsDeltaHook)), 0.1 ether);
    }

    function testSwap_noSwap_specifyInput() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        BalanceDelta delta = binSwapHelper.swap(
            key, true, -int128(1 ether), BinSwapHelper.TestSettings(true, true), abi.encode(1 ether, 0, 0)
        );

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        assertEq(amt0After - amt0Before, 0);
        assertEq(amt1After - amt1Before, 0);

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 0);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 1 ether);
    }

    function testSwap_noSwap_specifyOutput() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        // make sure hook has enough balance to pay
        token1.transfer(address(binReturnsDeltaHook), 1 ether);

        BalanceDelta delta =
            binSwapHelper.swap(key, true, 1 ether, BinSwapHelper.TestSettings(true, true), abi.encode(-1 ether, 0, 0));

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        // hook pays 1 ether of currency1 to user and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), 0);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 0 ether);

        assertEq(amt0After, amt0Before);
        assertEq(amt1After, amt1Before);
    }

    function testSwap_noSwap_returnUnspecifiedInBeforeSwap() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        token1.transfer(address(binReturnsDeltaHook), 1 ether);

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        BalanceDelta delta = binSwapHelper.swap(
            key, true, -int128(1 ether), BinSwapHelper.TestSettings(true, true), abi.encode(1 ether, -1 ether, 0)
        );

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        assertEq(amt0After - amt0Before, 0);
        assertEq(amt1After - amt1Before, 0);

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 1 ether);
        assertEq(token1.balanceOf(address(binReturnsDeltaHook)), 0 ether);
    }

    function testSwap_noSwap_returnUnspecifiedInBeforeSwapAndAfterSwap() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        token1.transfer(address(binReturnsDeltaHook), 1 ether);

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        BalanceDelta delta = binSwapHelper.swap(
            key,
            true,
            -int128(1 ether),
            BinSwapHelper.TestSettings(true, true),
            abi.encode(1 ether, -0.5 ether, -0.5 ether)
        );

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        assertEq(amt0After - amt0Before, 0);
        assertEq(amt1After - amt1Before, 0);

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 1 ether);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 1 ether);
        assertEq(token1.balanceOf(address(binReturnsDeltaHook)), 0 ether);
    }

    function testSwap_swapMore() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        token0.transfer(address(binReturnsDeltaHook), 1 ether);

        BalanceDelta delta = binSwapHelper.swap(
            key, true, -int128(1 ether), BinSwapHelper.TestSettings(true, true), abi.encode(-1 ether, 0, 0)
        );

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        assertEq(amt0After - amt0Before, 2 ether);
        assertEq(amt1Before - amt1After, 2 ether * 997 / 1000);

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 2 ether * 997 / 1000);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 0 ether);
    }

    function testSwap_swapLess() external {
        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 10 ether, 10 ether);
        binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        uint256 amt0Before = token0.balanceOf(address(vault));
        uint256 amt1Before = token1.balanceOf(address(vault));

        BalanceDelta delta = binSwapHelper.swap(
            key, true, -int128(1 ether), BinSwapHelper.TestSettings(true, true), abi.encode(0.5 ether, 0, 0)
        );

        uint256 amt0After = token0.balanceOf(address(vault));
        uint256 amt1After = token1.balanceOf(address(vault));

        assertEq(amt0After - amt0Before, 0.5 ether);
        assertEq(amt1Before - amt1After, 0.5 ether * 997 / 1000);

        // user pays 1 ether of currency0 to hook and no swap happens

        // trader's payment & return
        assertEq(delta.amount0(), -1 ether);
        assertEq(delta.amount1(), 0.5 ether * 997 / 1000);

        // hook's payment & return
        assertEq(token0.balanceOf(address(binReturnsDeltaHook)), 0.5 ether);
    }

    receive() external payable {}
}
