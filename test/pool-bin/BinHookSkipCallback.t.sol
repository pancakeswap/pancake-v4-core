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
import {BinSkipCallbackHook} from "./helpers/BinSkipCallbackHook.sol";

contract BinHookSkipCallbackTest is Test, GasSnapshot, BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinSkipCallbackHook public binSkipCallbackHook;

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

        binSkipCallbackHook = new BinSkipCallbackHook(iVault, iBinPoolManager);
        token0.approve(address(binSkipCallbackHook), 1000 ether);
        token1.approve(address(binSkipCallbackHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: binSkipCallbackHook,
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(binSkipCallbackHook.getHooksRegistrationBitmap())).setBinStep(10)
        });
    }

    function testInitialize_FromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));
        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testInitialize_NotfromHook() external {
        poolManager.initialize(key, activeId, new bytes(0));
        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 2);
    }

    function testMint_FromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, "");

        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 2);
    }

    function testMint_NotFromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binSkipCallbackHook.mint(key, mintParams, "");

        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testBurn_FromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binSkipCallbackHook.mint(key, mintParams, "");

        IBinPoolManager.BurnParams memory burnParams =
            _getSingleBinBurnLiquidityParams(key, poolManager, activeId, address(binSkipCallbackHook), 100);

        binSkipCallbackHook.burn(key, burnParams, "");

        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testBurn_NotFromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binLiquidityHelper.mint(key, mintParams, "");

        IBinPoolManager.BurnParams memory burnParams =
            _getSingleBinBurnLiquidityParams(key, poolManager, activeId, address(binLiquidityHelper), 100);

        binLiquidityHelper.burn(key, burnParams, "");

        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 4);
    }

    function testDonate_FromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binSkipCallbackHook.mint(key, mintParams, "");

        binSkipCallbackHook.donate(key, 10 ether, 10 ether, "");
        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 0);
    }

    function testDonate_NotFromHook() external {
        binSkipCallbackHook.initialize(key, activeId, new bytes(0));

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        binSkipCallbackHook.mint(key, mintParams, "");

        binDonateHelper.donate(key, 10 ether, 10 ether, "");
        assertEq(binSkipCallbackHook.hookCounterCallbackCount(), 2);
    }

    receive() external payable {}
}
