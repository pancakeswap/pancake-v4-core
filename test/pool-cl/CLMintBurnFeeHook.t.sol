// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
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
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {CLMintBurnFeeHook} from "./helpers/CLMintBurnFeeHook.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";

contract CLMintBurnFeeHookTest is Test, Deployers, TokenFixture {
    using CLPoolParametersHelper for bytes32;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    CLMintBurnFeeHook public clMintBurnFeeHook;

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
        clMintBurnFeeHook = new CLMintBurnFeeHook(vault, poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency0)).approve(address(clMintBurnFeeHook), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(clMintBurnFeeHook), 1000 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: clMintBurnFeeHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(clMintBurnFeeHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    /// @dev only meant for sanity test for the hook example
    function test_Mint() external {
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        // before
        assertEq(token0.balanceOf(address(this)), 10 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);
        assertEq(token0.balanceOf(address(vault)), 0 ether);
        assertEq(token1.balanceOf(address(vault)), 0 ether);
        assertEq(token0.balanceOf(address(clMintBurnFeeHook)), 0 ether);
        assertEq(token1.balanceOf(address(clMintBurnFeeHook)), 0 ether);

        // around 0.5 eth token0 / 0.5 eth token1 liquidity added
        (BalanceDelta delta,) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1000 ether, salt: 0}),
            ""
        );
        vm.snapshotGasLastCall("test_Mint");

        assertEq(token0.balanceOf(address(this)), 8500449895020996220); // ~8.5 ether
        assertEq(token1.balanceOf(address(this)), 8500449895020996220); // ~8.4 ether
        assertEq(token0.balanceOf(address(vault)), 1499550104979003780); // ~1.5 ether
        assertEq(token1.balanceOf(address(vault)), 1499550104979003780); // ~1.5 ether

        // hook mint VaultToken instead of taking token from vault as vault does not have token in this case
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency0), 999700069986002520); // ~1 eth
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency1), 999700069986002520); // ~1 eth
    }

    function test_Burn() external {
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        // around 0.5 eth token0 / 0.5 eth token1 liquidity added
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1000 ether, salt: 0}),
            ""
        );

        assertEq(token0.balanceOf(address(this)), 8500449895020996220); // ~8.5 ether
        assertEq(token1.balanceOf(address(this)), 8500449895020996220); // ~8.5 ether
        assertEq(token0.balanceOf(address(vault)), 1499550104979003780); // ~1.5 ether
        assertEq(token1.balanceOf(address(vault)), 1499550104979003780); // ~1.5 ether
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency0), 999700069986002520); // ~1 eth
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency1), 999700069986002520); // ~1 eth

        // remove liquidity
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: -1000 ether, salt: 0}),
            ""
        );
        vm.snapshotGasLastCall("test_Burn");

        // 8.5 to 7 eth = 1.5 eth diff :: -2 eth was taken by hook for fee and +0.5 was from remove liquidity
        assertEq(token0.balanceOf(address(this)), 7000899790041992443); // ~7 eth
        assertEq(token1.balanceOf(address(this)), 7000899790041992443); // ~7 eth

        // 1.5 to 3 eth = 1.5 eth diff :: -0.5 eth was returned to user and +2 eth deposited by hook
        assertEq(token0.balanceOf(address(vault)), 2999100209958007557); // ~3 eth
        assertEq(token1.balanceOf(address(vault)), 2999100209958007557); // ~3 eth

        // 1 to 3 eth = 2 eth diff :: + 2 eth as fee from remove liquidity
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency0), 2999100209958007556); // ~3 eth
        assertEq(vault.balanceOf(address(clMintBurnFeeHook), key.currency1), 2999100209958007556); // ~3 eth
    }

    receive() external payable {}
}
