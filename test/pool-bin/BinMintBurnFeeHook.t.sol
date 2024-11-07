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
import {BinLiquidityHelper} from "./helpers/BinLiquidityHelper.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {BinMintBurnFeeHook} from "./helpers/BinMintBurnFeeHook.sol";

contract BinMintBurnFeeHookTest is Test, GasSnapshot, BinTestHelper {
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinMintBurnFeeHook public binMintBurnFeeHook;

    BinLiquidityHelper public binLiquidityHelper;

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

        binLiquidityHelper = new BinLiquidityHelper(iBinPoolManager, iVault);
        token0.approve(address(binLiquidityHelper), 1000 ether);
        token1.approve(address(binLiquidityHelper), 1000 ether);

        binMintBurnFeeHook = new BinMintBurnFeeHook(iVault, iBinPoolManager);
        token0.approve(address(binMintBurnFeeHook), 1000 ether);
        token1.approve(address(binMintBurnFeeHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: binMintBurnFeeHook,
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(binMintBurnFeeHook.getHooksRegistrationBitmap())).setBinStep(10)
        });

        poolManager.initialize(key, activeId);
    }

    function test_Mint() external {
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        // before
        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 0 ether);
        assertEq(token0.balanceOf(address(binMintBurnFeeHook)), 0 ether);
        assertEq(token1.balanceOf(address(binMintBurnFeeHook)), 0 ether);

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        snapStart("BinMintBurnFeeHookTest#test_Mint");
        BalanceDelta delta = binLiquidityHelper.mint(key, mintParams, abi.encode(0));
        snapEnd();

        assertEq(token0.balanceOf(address(this)), 7 ether);
        assertEq(token1.balanceOf(address(this)), 7 ether);
        assertEq(token0.balanceOf(address(vault)), 3 ether);
        assertEq(token1.balanceOf(address(vault)), 3 ether);

        // hook mint VaultToken instead of taking token from vault as vault does not have token in this case
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency0), 2 ether);
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency1), 2 ether);
    }

    function test_Burn() external {
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        IBinPoolManager.MintParams memory mintParams = _getSingleBinMintParams(activeId, 1 ether, 1 ether);
        BalanceDelta delta = binLiquidityHelper.mint(key, mintParams, abi.encode(0));

        assertEq(token0.balanceOf(address(this)), 7 ether);
        assertEq(token1.balanceOf(address(this)), 7 ether);
        assertEq(token0.balanceOf(address(vault)), 3 ether);
        assertEq(token1.balanceOf(address(vault)), 3 ether);
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency0), 2 ether);
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency1), 2 ether);

        IBinPoolManager.BurnParams memory burnParams =
            _getSingleBinBurnLiquidityParams(key, poolManager, activeId, address(binLiquidityHelper), 100);
        snapStart("BinMintBurnFeeHookTest#test_Burn");
        binLiquidityHelper.burn(key, burnParams, "");
        snapEnd();

        // +1 from remove liqudiity, -4 from hook fee
        assertEq(token0.balanceOf(address(this)), 7 ether + 1 ether - 4 ether);
        assertEq(token1.balanceOf(address(this)), 7 ether + 1 ether - 4 ether);

        // -1 from remove liquidity, +4 from hook calling vault.mint
        assertEq(token0.balanceOf(address(vault)), 3 ether - 1 ether + 4 ether);
        assertEq(token1.balanceOf(address(vault)), 3 ether - 1 ether + 4 ether);
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency0), 2 ether + 4 ether);
        assertEq(vault.balanceOf(address(binMintBurnFeeHook), key.currency1), 2 ether + 4 ether);
    }

    receive() external payable {}
}
