// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Vault} from "../../src/Vault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {CLPool} from "../../src/pool-cl/libraries/CLPool.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {CLCustomCurveHook} from "./helpers/CLCustomCurveHook.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";

contract CLCustomCurveHookTest is Test, Deployers, TokenFixture, GasSnapshot {
    using CLPoolParametersHelper for bytes32;
    using LPFeeLibrary for uint24;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    CLCustomCurveHook public clCustomCurveHook;

    MockERC20 token0;
    MockERC20 token1;

    function setUp() public {
        initializeTokens();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // burn all tokens minted via initializeTokens
        token0.burn(address(this), token0.balanceOf(address(this)));
        token1.burn(address(this), token1.balanceOf(address(this)));
        (vault, poolManager) = createFreshManager();

        router = new CLPoolManagerRouter(vault, poolManager);
        clCustomCurveHook = new CLCustomCurveHook(vault, poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(clCustomCurveHook), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(clCustomCurveHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: clCustomCurveHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(clCustomCurveHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
        clCustomCurveHook.setPoolKey(key);
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    /// @dev only meant for sanity test for the hook example
    function test_addLiquidity_removeLiquidityXX() external {
        // pre-req: mint token on this contract
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 0 ether);

        // add liquidity and verify tokens are in the vault
        clCustomCurveHook.addLiquidity(1 ether, 2 ether);
        assertEq(token0.balanceOf(address(this)), 9 ether);
        assertEq(token1.balanceOf(address(this)), 8 ether);
        assertEq(token0.balanceOf(address(vault)), 1 ether);
        assertEq(token1.balanceOf(address(vault)), 2 ether);

        // remove liquidity and verify tokens are returned to this contract
        clCustomCurveHook.removeLiquidity(1 ether, 1 ether);
        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 9 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 1 ether);
    }

    function test_Swap_CustomCurve(uint256 _amtIn) public {
        // preq-req: add liqudiity
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);
        clCustomCurveHook.addLiquidity(4 ether, 8 ether);

        // before verify
        assertEq(token0.balanceOf(address(this)), 6 ether);
        assertEq(token1.balanceOf(address(this)), 2 ether);
        assertEq(token0.balanceOf(address(vault)), 4 ether);
        assertEq(token1.balanceOf(address(vault)), 8 ether);

        // swap exactIn token0 for token1
        uint128 amtIn = uint128(bound(_amtIn, 0.1 ether, 6 ether)); // 6 as token0.balanceOf(address(this) == 6 ethers

        snapStart("CLCustomCurveHookTest#test_Swap_CustomCurve");
        BalanceDelta delta = router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int128(amtIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );
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
