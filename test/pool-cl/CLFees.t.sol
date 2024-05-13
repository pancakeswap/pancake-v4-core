// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../../src/interfaces/IProtocolFees.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";
import {CLPool} from "../../src/pool-cl/libraries/CLPool.sol";
import {PoolIdLibrary} from "../../src/types/PoolId.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockHooks} from "./helpers/MockHooks.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {ProtocolFeeControllerTest} from "./helpers/ProtocolFeeControllerTest.sol";
import {IProtocolFeeController} from "../../src/interfaces/IProtocolFeeController.sol";
import {ProtocolFees} from "../../src/ProtocolFees.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ProtocolFeeLibrary} from "../../src/libraries/ProtocolFeeLibrary.sol";

contract CLFeesTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using CLPool for CLPool.State;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    IVault vault;
    CLPool.State state;
    CLPoolManager manager;

    CLPoolManagerRouter router;
    ProtocolFeeControllerTest protocolFeeController;

    MockHooks hook;
    PoolKey key;

    bool _zeroForOne = true;
    bool _oneForZero = false;

    function setUp() public {
        initializeTokens();
        (vault, manager) = Deployers.createFreshManager();

        router = new CLPoolManagerRouter(vault, manager);
        protocolFeeController = new ProtocolFeeControllerTest();
        MockERC20(Currency.unwrap(currency0)).approve(address(router), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(router), 10 ether);

        address hookAddr = address(99); // can't be a zero address, but does not have to have any other hook flags specified
        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        hook = MockHooks(hookAddr);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: manager,
            fee: uint24(3000),
            parameters: bytes32(uint256((60 << 16) | hook.getHooksRegistrationBitmap()))
        });

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testSetProtocolFeeControllerFuzz(uint24 protocolFee) public {
        (CLPool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, 0);

        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));

        uint24 protocolFee0 = protocolFee % 4096;
        uint24 protocolFee1 = protocolFee >> 12;

        if (protocolFee0 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE || protocolFee1 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
            vm.expectRevert(IProtocolFees.FeeTooLarge.selector);
            vm.prank(address(protocolFeeController));
            manager.setProtocolFee(key, protocolFee);
            return;
        }

        vm.prank(address(protocolFeeController));
        manager.setProtocolFee(key, protocolFee);

        (slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);
    }

    function testNoProtocolFee(uint24 protocolFee) public {
        // Early return instead of vm.assume (too many input rejected)
        if (protocolFee % 4096 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) return;
        if (protocolFee >> 12 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) return;

        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        vm.prank(address(protocolFeeController));
        manager.setProtocolFee(key, protocolFee);

        (CLPool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);

        int256 liquidityDelta = 10000;
        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams(-60, 60, liquidityDelta);
        router.modifyPosition(key, params, ZERO_BYTES);

        // Fees dont accrue for positive liquidity delta.
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        ICLPoolManager.ModifyLiquidityParams memory params2 =
            ICLPoolManager.ModifyLiquidityParams(-60, 60, -liquidityDelta);
        router.modifyPosition(key, params2, ZERO_BYTES);

        // add larger liquidity
        params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 10e18);
        router.modifyPosition(key, params, ZERO_BYTES);

        MockERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.swap(
            key,
            ICLPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            CLPoolManagerRouter.SwapTestSettings(true, true),
            ZERO_BYTES
        );

        uint256 expectedProtocolAmount1 = 10000 * (protocolFee >> 12) / ProtocolFeeLibrary.PIPS_DENOMINATOR;
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolAmount1);
    }

    function testCollectFees() public {
        uint24 protocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12); // 0.1% protocol fee
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        vm.prank(address(protocolFeeController));
        manager.setProtocolFee(key, protocolFee);

        (CLPool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-120, 120, 10e18);
        router.modifyPosition(key, params, ZERO_BYTES);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);
        router.swap(
            key,
            ICLPoolManager.SwapParams(false, 1000000, TickMath.MAX_SQRT_RATIO - 1),
            CLPoolManagerRouter.SwapTestSettings(true, true),
            ZERO_BYTES
        );

        uint256 expectedProtocolFees = 1000000 * 0.001;
        vm.prank(address(protocolFeeController));
        manager.collectProtocolFees(address(protocolFeeController), currency1, 0);
        assertEq(currency1.balanceOf(address(protocolFeeController)), expectedProtocolFees);
    }
}
