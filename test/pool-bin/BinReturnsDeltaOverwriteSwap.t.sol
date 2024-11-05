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
import {PackedUint128Math} from "../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../src/pool-bin/libraries/math/SafeCast.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {Constants} from "../../src/pool-bin/libraries/Constants.sol";
import {IBinHooks} from "../../src/pool-bin/interfaces/IBinHooks.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IBinHooks} from "../../src/pool-bin/interfaces/IBinHooks.sol";
import {BinSwapHelper} from "./helpers/BinSwapHelper.sol";
import {BinLiquidityHelper} from "./helpers/BinLiquidityHelper.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {BinReturnsDeltaHookOverwriteSwap} from "./helpers/BinReturnsDeltaHookOverwriteSwap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinReturnsDeltaOverwriteSwap is Test, GasSnapshot, BinTestHelper {
    using SafeCast for uint256;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinReturnsDeltaHookOverwriteSwap public binReturnsDeltaHookOverwriteSwap;

    BinSwapHelper public binSwapHelper;
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

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        IBinPoolManager iBinPoolManager = IBinPoolManager(address(poolManager));
        IVault iVault = IVault(address(vault));

        binSwapHelper = new BinSwapHelper(iBinPoolManager, iVault);
        binLiquidityHelper = new BinLiquidityHelper(iBinPoolManager, iVault);
        token0.approve(address(binSwapHelper), 1000 ether);
        token1.approve(address(binSwapHelper), 1000 ether);
        token0.approve(address(binLiquidityHelper), 1000 ether);
        token1.approve(address(binLiquidityHelper), 1000 ether);

        binReturnsDeltaHookOverwriteSwap = new BinReturnsDeltaHookOverwriteSwap(iVault, iBinPoolManager);
        token0.approve(address(binReturnsDeltaHookOverwriteSwap), 1000 ether);
        token1.approve(address(binReturnsDeltaHookOverwriteSwap), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: binReturnsDeltaHookOverwriteSwap,
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(binReturnsDeltaHookOverwriteSwap.getHooksRegistrationBitmap())).setBinStep(10)
        });
        binReturnsDeltaHookOverwriteSwap.setPoolKey(key);

        poolManager.initialize(key, activeId);
    }

    function testSwap_yy() external {
        console2.log("---------start of testSwap_yy add liquidity----------------------");
        console2.log("  reserveOfApp t0", vault.reservesOfApp(address(poolManager), key.currency0));
        console2.log("  reserveOfApp t1", vault.reservesOfApp(address(poolManager), key.currency1));
        console2.log("-------------------------------");

        // token will taken from the caller (this address) over
        binReturnsDeltaHookOverwriteSwap.addLiquidity(10 ether, 10 ether);

        console2.log("---------end of testSwap_yy add liquidity----------------------");
        console2.log("  reserveOfApp t0 (ethers)", vault.reservesOfApp(address(poolManager), key.currency0) / 1 ether);
        console2.log("  reserveOfApp t1 (ethers)", vault.reservesOfApp(address(poolManager), key.currency1) / 1 ether);
        console2.log("-------------------------------");
        console2.log("-------------------------------");

        console2.log("---------start of test_SwapYY swap----------------------");
        console2.log("  balanceof user t0: ", IERC20(Currency.unwrap(currency0)).balanceOf(address(this)) / 1 ether);
        console2.log("  balanceof user t1: ", IERC20(Currency.unwrap(currency1)).balanceOf(address(this)) / 1 ether);
        console2.log(
            "  balanceof hook t0: ",
            IERC20(Currency.unwrap(currency0)).balanceOf(address(binReturnsDeltaHookOverwriteSwap)) / 1 ether
        );
        console2.log(
            "  balanceof hook t1: ",
            IERC20(Currency.unwrap(currency1)).balanceOf(address(binReturnsDeltaHookOverwriteSwap)) / 1 ether
        );
        console2.log("  reserveOfApp t0 (ethers)", vault.reservesOfApp(address(poolManager), key.currency0) / 1 ether);
        console2.log("  reserveOfApp t1 (ethers)", vault.reservesOfApp(address(poolManager), key.currency1) / 1 ether);
        console2.log("--------------------------------------------------------------");

        BalanceDelta delta =
            binSwapHelper.swap(key, true, -int128(1 ether), BinSwapHelper.TestSettings(true, true), new bytes(0));

        console2.log("---------end of test_SwapYY swap----------------------");
        console2.log("  balanceof user t0: ", IERC20(Currency.unwrap(currency0)).balanceOf(address(this)) / 1 ether);
        console2.log("  balanceof user t1: ", IERC20(Currency.unwrap(currency1)).balanceOf(address(this)) / 1 ether);
        console2.log(
            "  balanceof hook t0: ",
            IERC20(Currency.unwrap(currency0)).balanceOf(address(binReturnsDeltaHookOverwriteSwap)) / 1 ether
        );
        console2.log(
            "  balanceof hook t1: ",
            IERC20(Currency.unwrap(currency1)).balanceOf(address(binReturnsDeltaHookOverwriteSwap)) / 1 ether
        );
        console2.log("  reserveOfApp t0 (ethers)", vault.reservesOfApp(address(poolManager), key.currency0) / 1 ether);
        console2.log("  reserveOfApp t1 (ethers)", vault.reservesOfApp(address(poolManager), key.currency1) / 1 ether);
        console2.log("-------------------------------");
    }

    receive() external payable {}
}
