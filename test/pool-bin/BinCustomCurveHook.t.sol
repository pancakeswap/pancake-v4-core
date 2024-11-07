// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IBinPoolManager} from "../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {Vault} from "../../src/Vault.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../../src/types/BalanceDelta.sol";
import {BinPoolManager} from "../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../src/pool-bin/libraries/BinPool.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinSwapHelper} from "./helpers/BinSwapHelper.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {BinCustomCurveHook} from "./helpers/BinCustomCurveHook.sol";

contract BinCustomCurveHookTest is Test, GasSnapshot, BinTestHelper {
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinCustomCurveHook public binCustomCurveHook;

    BinSwapHelper public binSwapHelper;

    uint24 activeId = 2 ** 23; // where token0 and token1 price is the same

    PoolKey key;
    bytes32 poolParam;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        vault = new Vault();
        poolManager = new BinPoolManager(IVault(address(vault)));

        vault.registerApp(address(poolManager));

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        IBinPoolManager iBinPoolManager = IBinPoolManager(address(poolManager));
        IVault iVault = IVault(address(vault));

        binSwapHelper = new BinSwapHelper(iBinPoolManager, iVault);
        token0.approve(address(binSwapHelper), 1000 ether);
        token1.approve(address(binSwapHelper), 1000 ether);

        binCustomCurveHook = new BinCustomCurveHook(iVault, iBinPoolManager);
        token0.approve(address(binCustomCurveHook), 1000 ether);
        token1.approve(address(binCustomCurveHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: binCustomCurveHook,
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(binCustomCurveHook.getHooksRegistrationBitmap())).setBinStep(10)
        });

        binCustomCurveHook.setPoolKey(key);
        poolManager.initialize(key, activeId);
    }

    /// @dev only meant for sanity test for the hook example
    function test_addLiquidity_removeLiquidity() external {
        // pre-req: mint token on this contract
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 0 ether);

        // add liquidity and verify tokens are in the vault
        binCustomCurveHook.addLiquidity(1 ether, 2 ether);
        assertEq(token0.balanceOf(address(this)), 9 ether);
        assertEq(token1.balanceOf(address(this)), 8 ether);
        assertEq(token0.balanceOf(address(vault)), 1 ether);
        assertEq(token1.balanceOf(address(vault)), 2 ether);

        // remove liquidity and verify tokens are returned to this contract
        binCustomCurveHook.removeLiquidity(1 ether, 1 ether);
        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 9 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 1 ether);
    }

    function test_Swap_CustomCurve(uint256 _amtIn) public {
        // preq-req: add liqudiity
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);
        binCustomCurveHook.addLiquidity(4 ether, 8 ether);

        // before verify
        assertEq(token0.balanceOf(address(this)), 6 ether);
        assertEq(token1.balanceOf(address(this)), 2 ether);
        assertEq(token0.balanceOf(address(vault)), 4 ether);
        assertEq(token1.balanceOf(address(vault)), 8 ether);

        // swap exactIn token0 for token1
        uint128 amtIn = uint128(bound(_amtIn, 0.1 ether, 6 ether)); // 6 as token0.balanceOf(address(this) == 6 ethers

        snapStart("BinCustomCurveHookTest#test_Swap_CustomCurve");
        BalanceDelta delta = binSwapHelper.swap(key, true, -int128(amtIn), BinSwapHelper.TestSettings(true, true), "");
        snapEnd();

        // verify 1:1 swap
        assertEq(delta.amount0(), -int128(amtIn));
        assertEq(delta.amount1(), int128(amtIn));

        // after verify
        assertEq(token0.balanceOf(address(this)), 6 ether - amtIn);
        assertEq(token1.balanceOf(address(this)), 2 ether + amtIn);
        assertEq(token0.balanceOf(address(vault)), 4 ether + amtIn);
        assertEq(token1.balanceOf(address(vault)), 8 ether - amtIn);
    }

    receive() external payable {}
}
