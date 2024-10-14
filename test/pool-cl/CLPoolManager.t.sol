// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {CLPool} from "../../src/pool-cl/libraries/CLPool.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";
import {IProtocolFees} from "../../src/interfaces/IProtocolFees.sol";
import "../../src/pool-cl/interfaces/ICLHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {FixedPoint96} from "../../src/pool-cl/libraries/FixedPoint96.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CLPosition} from "../../src/pool-cl/libraries/CLPosition.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture, MockERC20} from "../helpers/TokenFixture.sol";
import {MockHooks} from "./helpers/MockHooks.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {ParametersHelper} from "../../src/libraries/math/ParametersHelper.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {NonStandardERC20} from "./helpers/NonStandardERC20.sol";
import {MockProtocolFeeController} from "./helpers/ProtocolFeeControllers.sol";
import {IProtocolFeeController} from "../../src/interfaces/IProtocolFeeController.sol";
import {CLFeeManagerHook} from "./helpers/CLFeeManagerHook.sol";
import {ProtocolFeeLibrary} from "../../src/libraries/ProtocolFeeLibrary.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";
import {NoIsolate} from "../helpers/NoIsolate.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CLPoolGetter} from "./helpers/CLPoolGetter.sol";
import {CLSlot0} from "../../src/pool-cl/types/CLSlot0.sol";

contract CLPoolManagerTest is Test, NoIsolate, Deployers, TokenFixture, GasSnapshot {
    using CLPoolParametersHelper for bytes32;
    using ParametersHelper for bytes32;
    using LPFeeLibrary for uint24;
    using Hooks for bytes32;
    using CLPoolGetter for CLPoolManager;

    error ContractSizeTooLarge(uint256 diff);

    event Transfer(address caller, address indexed from, address indexed to, Currency indexed currency, uint256 amount);
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFees);
    event DynamicLPFeeUpdated(PoolId indexed id, uint24 dynamicLPFee);

    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    MockProtocolFeeController public feeController;
    CLFeeManagerHook public clFeeManagerHook;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();
        router = new CLPoolManagerRouter(vault, poolManager);
        feeController = new MockProtocolFeeController();
        clFeeManagerHook = new CLFeeManagerHook(poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 10 ether);
    }

    function test_bytecodeSize() public {
        snapSize("CLPoolManagerBytecodeSize", address(poolManager));

        // forge coverage will run with '--ir-minimum' which set optimizer run to min
        // thus we do not want to revert for forge coverage case
        if (vm.envExists("FOUNDRY_PROFILE") && address(poolManager).code.length > 24576) {
            revert ContractSizeTooLarge(address(poolManager).code.length - 24576);
        }
    }

    // **************              *************** //
    // **************  initialize  *************** //
    // **************              *************** //
    function testInitialize_feeRange() external {
        // 3000 i.e. 0.3%
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0xa0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 0
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(0),
                parameters: bytes32(uint256(0xa0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 300000 i.e. 30%
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(300000),
                parameters: bytes32(uint256(0xa0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 1000000 i.e. 100%
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(1000000),
                parameters: bytes32(uint256(0xa0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 1000001 i.e. > 100%
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(1000001),
                parameters: bytes32(uint256(0xa0000))
            });

            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, uint24(1000001)));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }
    }

    function testInitialize_tickSpacing() external {
        // tickSpacing 0
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x0000))
            });

            vm.expectRevert(abi.encodeWithSelector(ICLPoolManager.TickSpacingTooSmall.selector, int24(0)));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // tickSpacing 1
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x10000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // tickSpacing 10
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0xa0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // tickSpacing max
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x7fff0000))
            });

            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // tickSpacing overflow
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x80000000))
            });

            vm.expectRevert(abi.encodeWithSelector(ICLPoolManager.TickSpacingTooLarge.selector, int24(0x8000)));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }
    }

    function testInitialize_unusedBits() external {
        // 1 at 39 bit
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x18000010000))
            });

            // 0x800001 = -8388607
            vm.expectRevert(abi.encodeWithSelector(ICLPoolManager.TickSpacingTooSmall.selector, -8388607));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 1 at 40 bit
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x10000010000))
            });

            vm.expectRevert(abi.encodeWithSelector(ParametersHelper.UnusedBitsNonZero.selector));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 1 at 41 bit
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x20000010000))
            });

            vm.expectRevert(abi.encodeWithSelector(ParametersHelper.UnusedBitsNonZero.selector));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // 1 at 42 bit
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(address(0)),
                poolManager: poolManager,
                fee: uint24(3000),
                parameters: bytes32(uint256(0x40000010000))
            });

            vm.expectRevert(abi.encodeWithSelector(ParametersHelper.UnusedBitsNonZero.selector));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }
    }

    function testInitialize_HookValidation() external {
        MockHooks hookAddr = new MockHooks();

        // hook config
        {
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(hookAddr),
                poolManager: poolManager,
                fee: uint24(3000),
                // 0 ~ 15  hookRegistrationMap = 0x1
                // 16 ~ 24 tickSpacing = 10
                parameters: bytes32(uint256(0xa0001))
            });

            vm.expectRevert(abi.encodeWithSelector(Hooks.HookConfigValidationError.selector));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }

        // hook permission
        {
            // beforeSwap is disabled but beforeSwapReturnsDelta is enabled
            hookAddr.setHooksRegistrationBitmap(uint16(1 << HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET));
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(makeAddr("token0")),
                currency1: Currency.wrap(makeAddr("token1")),
                hooks: IHooks(hookAddr),
                poolManager: poolManager,
                fee: uint24(3000),
                // 0 ~ 15  hookRegistrationMap =
                // 16 ~ 24 tickSpacing = 10
                parameters: bytes32(uint256(0xa0000) | hookAddr.getHooksRegistrationBitmap())
            });

            vm.expectRevert(abi.encodeWithSelector(Hooks.HookPermissionsValidationError.selector));
            poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        }
    }

    function testInitialize_stateCheck() external {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(makeAddr("token0")),
            currency1: Currency.wrap(makeAddr("token1")),
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 10
            parameters: bytes32(uint256(0xa0000))
        });

        poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);

        (CLSlot0 slot0, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, uint128 liquidity) =
            poolManager.pools(key.toId());

        assertEq(slot0.sqrtPriceX96(), TickMath.MIN_SQRT_RATIO);
        assertEq(slot0.tick(), TickMath.MIN_TICK);
        assertEq(slot0.protocolFee(), 0);
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);
        assertEq(liquidity, 0);
    }

    function testInitialize_gasCheck_withoutHooks() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 10
            parameters: bytes32(uint256(0xa0000))
        });

        snapStart("CLPoolManagerTest#initializeWithoutHooks");
        poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);
        snapEnd();
    }

    function test_initialize_fuzz(PoolKey memory key, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        // tested in Hooks.t.sol
        key.hooks = IHooks(address(0));
        key.poolManager = poolManager;

        if (key.parameters.getTickSpacing() > TickMath.MAX_TICK_SPACING) {
            vm.expectRevert(
                abi.encodeWithSelector(ICLPoolManager.TickSpacingTooLarge.selector, key.parameters.getTickSpacing())
            );
            poolManager.initialize(key, sqrtPriceX96);
        } else if (key.parameters.getTickSpacing() < TickMath.MIN_TICK_SPACING) {
            vm.expectRevert(
                abi.encodeWithSelector(ICLPoolManager.TickSpacingTooSmall.selector, key.parameters.getTickSpacing())
            );
            poolManager.initialize(key, sqrtPriceX96);
        } else if (key.currency0 > key.currency1 || key.currency0 == key.currency1) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPoolManager.CurrenciesInitializedOutOfOrder.selector, key.currency0, key.currency1
                )
            );
            poolManager.initialize(key, sqrtPriceX96);
        } else if (!checkUnusedBitsAllZero(key.parameters)) {
            vm.expectRevert(abi.encodeWithSelector(ParametersHelper.UnusedBitsNonZero.selector));
            poolManager.initialize(key, sqrtPriceX96);
        } else if (!_validateHookConfig(key)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookConfigValidationError.selector));
            poolManager.initialize(key, sqrtPriceX96);
        } else if (!_validateHookPermissionsConflict(key)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookPermissionsValidationError.selector));
            poolManager.initialize(key, sqrtPriceX96);
        } else if (key.fee > LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, key.fee));
            poolManager.initialize(key, sqrtPriceX96);
        } else {
            int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            vm.expectEmit(true, true, true, true);
            emit ICLPoolManager.Initialize(
                key.toId(), key.currency0, key.currency1, key.hooks, key.fee, key.parameters, sqrtPriceX96, tick
            );
            poolManager.initialize(key, sqrtPriceX96);

            (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
            assertEq(slot0.sqrtPriceX96(), sqrtPriceX96);
            assertEq(slot0.protocolFee(), 0);
        }
    }

    function test_initialize_forNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60 << 16))
        });

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Initialize(
            key.toId(),
            key.currency0,
            key.currency1,
            key.hooks,
            key.fee,
            key.parameters,
            sqrtPriceX96,
            TickMath.getTickAtSqrtRatio(sqrtPriceX96)
        );
        poolManager.initialize(key, sqrtPriceX96);

        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(slot0.protocolFee(), 0);
        assertEq(slot0.tick(), TickMath.getTickAtSqrtRatio(sqrtPriceX96));
    }

    function test_initialize_succeedsWithHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        MockHooks hookAddr = new MockHooks();
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(hookAddr),
            poolManager: poolManager,
            parameters: bytes32(uint256((60 << 16) | hookAddr.getHooksRegistrationBitmap()))
        });

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        bytes memory beforePayload =
            abi.encodeWithSelector(MockHooks.beforeInitialize.selector, address(this), key, sqrtPriceX96);

        bytes memory afterPayload =
            abi.encodeWithSelector(MockHooks.afterInitialize.selector, address(this), key, sqrtPriceX96, tick);

        vm.expectCall(address(hookAddr), 0, beforePayload, 1);
        vm.expectCall(address(hookAddr), 0, afterPayload, 1);

        poolManager.initialize(key, sqrtPriceX96);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96(), sqrtPriceX96);

        (Currency curr0, Currency curr1, IHooks hooks, IPoolManager pm, uint24 fee, bytes32 parameters) =
            poolManager.poolIdToPoolKey(key.toId());
        assertEq(Currency.unwrap(curr0), Currency.unwrap(key.currency0));
        assertEq(Currency.unwrap(curr1), Currency.unwrap(key.currency1));
        assertEq(address(hooks), address(key.hooks));
        assertEq(address(pm), address(key.poolManager));
        assertEq(fee, key.fee);
        assertEq(parameters, key.parameters);
    }

    function test_initialize_succeedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(int256(TickMath.MAX_TICK_SPACING) << 16))
        });

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Initialize(
            key.toId(),
            key.currency0,
            key.currency1,
            key.hooks,
            key.fee,
            key.parameters,
            sqrtPriceX96,
            TickMath.getTickAtSqrtRatio(sqrtPriceX96)
        );

        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_succeedsWithEmptyHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        MockHooks hookEmptyAddr = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: hookEmptyAddr,
            poolManager: poolManager,
            parameters: bytes32(uint256((60 << 16) | hookEmptyAddr.getHooksRegistrationBitmap()))
        });

        poolManager.initialize(key, sqrtPriceX96);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96(), sqrtPriceX96);
    }

    function test_initialize_revertsWithIdenticalTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        // Both currencies are currency0
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency0,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60 << 16))
        });

        vm.expectRevert(
            abi.encodeWithSelector(IPoolManager.CurrenciesInitializedOutOfOrder.selector, key.currency0, key.currency1)
        );
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_revertsWithSameTokenCombo(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60 << 16))
        });

        PoolKey memory keyInvertedCurrency = PoolKey({
            currency0: currency1,
            currency1: currency0,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60 << 16))
        });

        poolManager.initialize(key, sqrtPriceX96);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.CurrenciesInitializedOutOfOrder.selector,
                keyInvertedCurrency.currency0,
                keyInvertedCurrency.currency1
            )
        );
        poolManager.initialize(keyInvertedCurrency, sqrtPriceX96);
    }

    function test_initialize_revertsWhenPoolAlreadyInitialized(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60 << 16))
        });

        poolManager.initialize(key, sqrtPriceX96);
        vm.expectRevert(CLPool.PoolAlreadyInitialized.selector);
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_failsWithIncorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));

        // Fails at beforeInitialize hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        poolManager.initialize(key, SQRT_RATIO_1_1);

        // Fail at afterInitialize hook.
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function test_initialize_succeedsWithCorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, mockHooks.afterInitialize.selector);

        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function test_initialize_failsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256((int256((TickMath.MAX_TICK_SPACING)) + 1) << 16))
        });

        vm.expectRevert(
            abi.encodeWithSelector(ICLPoolManager.TickSpacingTooLarge.selector, TickMath.MAX_TICK_SPACING + 1)
        );
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_failsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(0))
        });

        vm.expectRevert(abi.encodeWithSelector(ICLPoolManager.TickSpacingTooSmall.selector, 0));
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_failsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            // tickSpacing = -1
            parameters: bytes32(uint256(0xffffff) << 16)
        });

        vm.expectRevert(abi.encodeWithSelector(ICLPoolManager.TickSpacingTooSmall.selector, -1));
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_initialize_failsIDynamicFeeTooLarge(uint24 dynamicSwapFee) public {
        dynamicSwapFee = uint24(bound(dynamicSwapFee, LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE + 1, type(uint24).max));

        clFeeManagerHook.setHooksRegistrationBitmap(uint16(1 << HOOKS_AFTER_INITIALIZE_OFFSET));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: CLPoolParametersHelper.setTickSpacing(
                bytes32(uint256(clFeeManagerHook.getHooksRegistrationBitmap())), 10
            )
        });

        clFeeManagerHook.setFee(dynamicSwapFee);
        vm.expectRevert(
            abi.encodeWithSelector(
                Hooks.Wrap__FailedHookCall.selector,
                clFeeManagerHook,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, dynamicSwapFee)
            )
        );
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function test_initialize_failsDynamicFeeInvalid() public {
        clFeeManagerHook.setHooksRegistrationBitmap(uint16(1 << HOOKS_AFTER_INITIALIZE_OFFSET));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG + 1,
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: CLPoolParametersHelper.setTickSpacing(
                bytes32(uint256(clFeeManagerHook.getHooksRegistrationBitmap())), 10
            )
        });

        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, LPFeeLibrary.DYNAMIC_FEE_FLAG + 1));
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    // **************                  *************** //
    // **************  modifyPosition  *************** //
    // **************                  *************** //

    function testModifyPosition_addLiquidity() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e10 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e10 ether);

        uint256 token0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        snapStart("CLPoolManagerTest#addLiquidity_fromEmpty");
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e24,
                salt: 0
            }),
            ""
        );
        snapEnd();

        {
            uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
            uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

            // consume both X and Y, python:
            // >>> X = ((1.0001 ** tick0) ** -0.5 - (1.0001 ** tick1) ** -0.5) * 1e24
            // >>> Y = ((1.0001 ** tick1) ** 0.5 - (1.0001 ** tick0) ** 0.5) * 1e24
            assertEq(token0Before - token0Left, 99999999999999999945788);
            assertEq(token1Before - token1Left, 9999999999999999999945788);

            assertEq(poolManager.getLiquidity(key.toId()), 1e24);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0), 1e24
            );

            assertEq(
                poolManager.getPosition(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0)
                    .feeGrowthInside0LastX128,
                0
            );
            assertEq(
                poolManager.getPosition(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0)
                    .feeGrowthInside1LastX128,
                0
            );
        }

        snapStart("CLPoolManagerTest#addLiquidity_fromNonEmpty");
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e4,
                salt: 0
            }),
            ""
        );
        snapEnd();

        {
            uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
            uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

            // consume both X and Y, python:
            // >>> X = ((1.0001 ** tick0) ** -0.5 - (1.0001 ** tick1) ** -0.5) * 1e24
            // >>> Y = ((1.0001 ** tick1) ** 0.5 - (1.0001 ** tick0) ** 0.5) * 1e24
            assertEq(token0Before - token0Left, 99999999999999999946788);
            assertEq(token1Before - token1Left, 10000000000000000000045788);

            assertEq(poolManager.getLiquidity(key.toId()), 1e24 + 1e4);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0),
                1e24 + 1e4
            );

            assertEq(
                poolManager.getPosition(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0)
                    .feeGrowthInside0LastX128,
                0
            );
            assertEq(
                poolManager.getPosition(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0)
                    .feeGrowthInside1LastX128,
                0
            );
        }
    }

    function testModifyPosition_feeDelta() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        BalanceDelta feeDelta;
        // Step 1: Add liquidity to new pool, verify feeDelta = 0
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e18,
                salt: 0
            }),
            ""
        );
        assertTrue(feeDelta == BalanceDeltaLibrary.ZERO_DELTA);

        // Step 2: Add liquidity again to pool, verify feeDelta = 0
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e18,
                salt: 0
            }),
            ""
        );
        assertTrue(feeDelta == BalanceDeltaLibrary.ZERO_DELTA);

        // step 3: Remove liquidity from pool, verify feeDelta = 0
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: -1e18,
                salt: 0
            }),
            ""
        );
        assertTrue(feeDelta == BalanceDeltaLibrary.ZERO_DELTA);

        // step 4: Perform a swap then add liquidity, verify feeDelta != 0
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e18,
                salt: 0
            }),
            ""
        );

        // amt0 & amt1 are positive i.e. the pool owes us tokens
        assertApproxEqRel(uint256(int256(feeDelta.amount0())), 0.003 * 0.1 ether, 1e16); // around 0.3% fee

        // step 5: Add liquidity, verify feeDelta == 0
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e18,
                salt: 0
            }),
            ""
        );
        assertTrue(feeDelta == BalanceDeltaLibrary.ZERO_DELTA);

        // step 6: Perform a swap then remove liquidity, verify feeDelta != 0
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );
        (, feeDelta) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: -1e18,
                salt: 0
            }),
            ""
        );

        // amt0 & amt1 are non positive i.e. the pool owes us tokens
        assertApproxEqRel(uint256(int256(feeDelta.amount0())), 0.003 * 0.1 ether, 1e16); // around 0.3% fee
    }

    function testModifyPosition_Liquidity_aboveCurrentTick() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);
        uint256 token0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46055, tickUpper: 46060, liquidityDelta: 1e9, salt: 0}),
            ""
        );

        uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // consume X only, python:
        // >>> ((1.0001 ** tick0) ** -0.5 - (1.0001 ** tick1) ** -0.5) * 1e9
        // 24994.381475337836
        assertEq(token0Before - token0Left, 24995);
        assertEq(token1Before - token1Left, 0);

        // no active liquidity
        assertEq(poolManager.getLiquidity(key.toId()), 0);
        assertEq(poolManager.getLiquidity(key.toId(), address(router), 46055, 46060, 0), 1e9);

        assertEq(poolManager.getPosition(key.toId(), address(this), 46055, 46060, 0).feeGrowthInside0LastX128, 0);
        assertEq(poolManager.getPosition(key.toId(), address(this), 46055, 46060, 0).feeGrowthInside1LastX128, 0);
    }

    function testModifyPosition_addLiquidity_belowCurrentTick() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);
        uint256 token0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: 1e9, salt: 0}),
            ""
        );

        uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // consume Y only, python:
        //>>> ((1.0001 ** tick1) ** 0.5 - (1.0001 ** tick0) ** 0.5) * 1e9
        // 24962530.97288914
        assertEq(token0Before - token0Left, 0);
        assertEq(token1Before - token1Left, 24962531);

        // no active liquidity
        assertEq(poolManager.getLiquidity(key.toId()), 0);
        assertEq(poolManager.getLiquidity(key.toId(), address(router), 46000, 46050, 0), 1e9);

        assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside0LastX128, 0);
        assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside1LastX128, 0);
    }

    function testModifyPosition_removeLiquidity_fromEmpty() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: -1, salt: 0}),
            ""
        );
    }

    function testModifyPosition_removeLiquidity_updateEmptyPosition() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        vm.expectRevert(CLPosition.CannotUpdateEmptyPosition.selector);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: 0, salt: 0}),
            ""
        );
    }

    function testModifyPosition_removeLiquidity_empty() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 1 i.e. tick 0
        poolManager.initialize(key, uint160(1 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -1, tickUpper: 1, liquidityDelta: 100 ether, salt: 0}),
            ""
        );

        assertEq(poolManager.getLiquidity(key.toId()), 100 ether, "total liquidity should be 1000");
        assertEq(
            poolManager.getLiquidity(key.toId(), address(router), -1, 1, 0),
            100 ether,
            "router's liquidity should be 1000"
        );

        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 4999625031247266);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 4999625031247266);

        assertEq(poolManager.getPosition(key.toId(), address(router), -1, 1, 0).feeGrowthInside0LastX128, 0);
        assertEq(poolManager.getPosition(key.toId(), address(router), -1, 1, 0).feeGrowthInside1LastX128, 0);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -1, tickUpper: 1, liquidityDelta: -100 ether, salt: 0}),
            ""
        );

        assertEq(poolManager.getLiquidity(key.toId()), 0);
        assertEq(poolManager.getLiquidity(key.toId(), address(router), -1, 1, 0), 0);

        // expected to receive 0, but got 1 because of precision loss
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 1);
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 1);

        assertEq(poolManager.getPosition(key.toId(), address(router), -1, 1, 0).feeGrowthInside0LastX128, 0);
        assertEq(poolManager.getPosition(key.toId(), address(router), -1, 1, 0).feeGrowthInside1LastX128, 0);
    }

    function testModifyPosition_removeLiquidity_halfAndThenAll() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);
        uint256 token0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 token1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: 1e9, salt: 0}),
            ""
        );

        {
            uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
            uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

            // consume Y only, python:
            //>>> ((1.0001 ** tick1) ** 0.5 - (1.0001 ** tick0) ** 0.5) * 1e9
            // 24962530.97288914
            assertEq(token0Before - token0Left, 0);
            assertEq(token1Before - token1Left, 24962531);

            // no active liquidity
            assertEq(poolManager.getLiquidity(key.toId()), 0);
            assertEq(poolManager.getLiquidity(key.toId(), address(router), 46000, 46050, 0), 1e9);

            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside0LastX128, 0);
            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside1LastX128, 0);
        }

        // remove half
        snapStart("CLPoolManagerTest#removeLiquidity_toNonEmpty");
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: -5 * 1e8, salt: 0}),
            ""
        );
        snapEnd();

        {
            uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
            uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

            // half of 24962531
            assertEq(token0Before - token0Left, 0);
            assertEq(token1Before - token1Left, 12481266);

            // no active liquidity
            assertEq(poolManager.getLiquidity(key.toId()), 0);
            assertEq(poolManager.getLiquidity(key.toId(), address(router), 46000, 46050, 0), 5 * 1e8);

            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside0LastX128, 0);
            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside1LastX128, 0);
        }

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 46000, tickUpper: 46050, liquidityDelta: -5 * 1e8, salt: 0}),
            ""
        );

        {
            uint256 token0Left = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
            uint256 token1Left = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

            // back to 0
            assertEq(token0Before - token0Left, 0);

            // expected to receive 0, but got 1 because of precision loss
            assertEq(token1Before - token1Left, 1);

            // no active liquidity
            assertEq(poolManager.getLiquidity(key.toId()), 0);
            assertEq(poolManager.getLiquidity(key.toId(), address(router), 46000, 46050, 0), 0);

            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside0LastX128, 0);
            assertEq(poolManager.getPosition(key.toId(), address(router), 46000, 46050, 0).feeGrowthInside1LastX128, 0);
        }
    }

    function testModifyPosition_failsIfNotInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });
        vm.expectRevert();
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0}),
            ZERO_BYTES
        );
    }

    function testModifyPosition_succeedsIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        poolManager.initialize(key, sqrtPriceX96);

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.ModifyLiquidity(key.toId(), address(router), 0, 60, 100, 0);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0}),
            ZERO_BYTES
        );
    }

    function testModifyPosition_succeedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        poolManager.initialize(key, sqrtPriceX96);
        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.ModifyLiquidity(key.toId(), address(router), 0, 60, 100, 0);

        router.modifyPosition{value: 100}(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0}),
            ZERO_BYTES
        );
    }

    function testModifyPosition_succeedsWithHooksIfFeesAccruedNonZero(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = SQRT_RATIO_1_1;

        MockHooks mockAddr = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(mockAddr),
            poolManager: poolManager,
            parameters: bytes32((uint256(60) << 16) | mockAddr.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 100, salt: 0});

        poolManager.initialize(key, sqrtPriceX96);

        router.modifyPosition(key, params, ZERO_BYTES);

        // perform a donate to generate some fee
        router.donate(key, 1e18, 1e18, ZERO_BYTES);

        BalanceDelta balanceDelta;
        // create a new context to swallow up the revert
        try CLPoolManagerTest(payable(this)).tryExecute(
            address(router),
            abi.encodeWithSelector(CLPoolManagerRouter.modifyPosition.selector, key, params, ZERO_BYTES)
        ) {
            revert("must revert");
        } catch (bytes memory result) {
            balanceDelta = abi.decode(result, (BalanceDelta));
        }
        bytes memory afterPayload = abi.encodeWithSelector(
            MockHooks.afterAddLiquidity.selector,
            address(router),
            key,
            params,
            balanceDelta,
            toBalanceDelta(1e18, 1e18),
            ZERO_BYTES
        );

        vm.expectCall(address(mockAddr), 0, afterPayload, 1);
        router.modifyPosition(key, params, ZERO_BYTES);
    }

    function testModifyPosition_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        MockHooks mockAddr = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(mockAddr),
            poolManager: poolManager,
            parameters: bytes32((uint256(60) << 16) | mockAddr.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        poolManager.initialize(key, sqrtPriceX96);

        BalanceDelta balanceDelta;
        // create a new context to swallow up the revert
        try CLPoolManagerTest(payable(this)).tryExecute(
            address(router),
            abi.encodeWithSelector(CLPoolManagerRouter.modifyPosition.selector, key, params, ZERO_BYTES)
        ) {
            revert("must revert");
        } catch (bytes memory result) {
            balanceDelta = abi.decode(result, (BalanceDelta));
        }

        bytes memory beforePayload =
            abi.encodeWithSelector(MockHooks.beforeAddLiquidity.selector, address(router), key, params, ZERO_BYTES);

        bytes memory afterPayload = abi.encodeWithSelector(
            MockHooks.afterAddLiquidity.selector,
            address(router),
            key,
            params,
            balanceDelta,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );

        vm.expectCall(address(mockAddr), 0, beforePayload, 1);
        vm.expectCall(address(mockAddr), 0, afterPayload, 1);
        router.modifyPosition(key, params, ZERO_BYTES);
    }

    function testModifyPosition_succeedsWithHooksIfLiquidityDeltaIsZero(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        MockHooks mockAddr = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(mockAddr),
            poolManager: poolManager,
            parameters: bytes32((uint256(60) << 16) | mockAddr.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        poolManager.initialize(key, sqrtPriceX96);

        // make sure there is some liquidity
        router.modifyPosition(key, params, ZERO_BYTES);

        params.liquidityDelta = 0;

        bytes memory beforePayload =
            abi.encodeWithSelector(MockHooks.beforeRemoveLiquidity.selector, address(router), key, params, ZERO_BYTES);

        bytes memory afterPayload = abi.encodeWithSelector(
            MockHooks.afterRemoveLiquidity.selector,
            address(router),
            key,
            params,
            BalanceDeltaLibrary.ZERO_DELTA,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );

        vm.expectCall(address(mockAddr), 0, beforePayload, 1);
        vm.expectCall(address(mockAddr), 0, afterPayload, 1);
        router.modifyPosition(key, params, ZERO_BYTES);
    }

    function testModifyPosition_failsWithIncorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32((uint256(10) << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        poolManager.initialize(key, SQRT_RATIO_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));

        // Fails at beforeAddLiquidity hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.modifyPosition(key, params, ZERO_BYTES);

        // Fail at afterAddLiquidity hook.
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.modifyPosition(key, params, ZERO_BYTES);
    }

    function testModifyPosition_succeedsWithCorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32((uint256(10) << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        poolManager.initialize(key, SQRT_RATIO_1_1);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, mockHooks.afterAddLiquidity.selector);

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.ModifyLiquidity(key.toId(), address(router), 0, 60, 100, 0);

        router.modifyPosition(key, params, ZERO_BYTES);
    }

    function testModifyPosition_withNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);

        snapStart("CLPoolManagerTest#addLiquidity_nativeToken");
        router.modifyPosition{value: 100}(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0}),
            ZERO_BYTES
        );
        snapEnd();
    }

    function testModifyPosition_withSalt_addAndRemove() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);
        bytes32 salt = bytes32(uint256(0x1234));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e24,
                salt: salt
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24);

            // salt = 0 returns nothing
            assertEq(poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0), 0);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt), 1e24
            );
        }

        // add into that position
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e4,
                salt: salt
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24 + 1e4);
            assertEq(poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0), 0);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt),
                1e24 + 1e4
            );
        }

        // decrease liquidity
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: -1e4,
                salt: salt
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24);
            assertEq(poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, 0), 0);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt), 1e24
            );
        }
    }

    function testModifyPosition_mixWithAndWithoutSalt() external {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);

        bytes32 salt0 = bytes32(0);
        bytes32 salt1 = bytes32(uint256(0x1234));
        bytes32 salt2 = bytes32(uint256(0x5678));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e24,
                salt: salt1
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24);

            // both salt0 & salt2 remains 0
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt0), 0
            );
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt1), 1e24
            );
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt2), 0
            );
        }

        // add into another salt
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e4,
                salt: salt2
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24 + 1e4);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt0), 0
            );
            // salt1 position should be untouched
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt1), 1e24
            );

            // salt2 position should be updated
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt2), 1e4
            );
        }

        // add into another salt
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e10,
                salt: salt0
            }),
            ""
        );

        {
            assertEq(poolManager.getLiquidity(key.toId()), 1e24 + 1e4 + 1e10);
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt0), 1e10
            );
            // salt1 & salt2 positions should be untouched
            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt1), 1e24
            );

            assertEq(
                poolManager.getLiquidity(key.toId(), address(router), TickMath.MIN_TICK, TickMath.MAX_TICK, salt2), 1e4
            );
        }
    }

    // **************        *************** //
    // **************  swap  *************** //
    // **************        *************** //

    function testSwap_runOutOfLiquidity() external {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            // 0 ~ 15  hookRegistrationMap = nil
            // 16 ~ 24 tickSpacing = 1
            parameters: bytes32(uint256(0x10000))
        });

        // price = 100 tick roughly 46054
        poolManager.initialize(key, uint160(10 * FixedPoint96.Q96));

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e30 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e30 ether);

        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: 46053,
                tickUpper: 46055,
                liquidityDelta: 1000000 ether,
                salt: 0
            }),
            ""
        );

        // token0: roughly 5 ether
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)), 4977594234867895338);
        // token1: roughly 502 ether
        assertEq(IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)), 502165582277283491084);

        // swap 10 ether token0 for token1
        snapStart("CLPoolManagerTest#swap_runOutOfLiquidity");
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 10 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );
        snapEnd();

        console2.log("token0 balance: ", IERC20(Currency.unwrap(currency0)).balanceOf(address(vault)));
        console2.log("token1 balance: ", IERC20(Currency.unwrap(currency1)).balanceOf(address(vault)));
    }

    function testSwap_failsIfNotInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: sqrtPriceX96});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectRevert();
        router.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwap_succeedsIfInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory modifyPositionParams =
            ICLPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0});

        router.modifyPosition(key, modifyPositionParams, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Swap(
            key.toId(), address(router), -100, 98, 79228162514264329749955861424, 1000000000000000000, -1, 3000, 0
        );

        // sell base token(x) for quote token(y), pricea(y / x) decreases
        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        router.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwap_succeedsIfInitialized_WithDynamicFee() public {
        uint16 bitMap = 0x0040; // 0000 0000 0100 0000 (before swap call)
        clFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, // 0.3%
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: bytes32(uint256((60 << 16) | clFeeManagerHook.getHooksRegistrationBitmap()))
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory modifyPositionParams =
            ICLPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0});

        router.modifyPosition(key, modifyPositionParams, ZERO_BYTES);

        // similar result to testSwap_succeedsIfInitialized above, except swapFee is twice due to dynamic fee
        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Swap(
            key.toId(), address(router), -100, 97, 79228162514264329829184023939, 1000000000000000000, -1, 12000, 0
        );

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        bytes memory data = abi.encode(true, uint24(12000)); // dynamic fee at 1.2% (four times of static fee)
        router.swap(key, params, testSettings, data);
    }

    function testSwap_succeeds_withBothFeeEnabled() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            // 0.3%
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
        poolManager.setProtocolFeeController(feeController);

        // 0.1%
        vm.prank(address(feeController));
        poolManager.setProtocolFee(
            key, ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12)
        );

        ICLPoolManager.ModifyLiquidityParams memory modifyPositionParams =
            ICLPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0});

        router.modifyPosition(key, modifyPositionParams, ZERO_BYTES);

        // 0.1% protocol fee first then 0.3% lp fee charged for the remaining i.e. 0.3997% in total
        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Swap(
            key.toId(),
            address(router),
            // amt0 = -3013394245478362 and amt1 = 2995354955910780 if it goes without protocol fee
            -3016410656134496,
            2995354955910780,
            56022770974786139918731938227,
            0,
            -6932,
            3997,
            1000
        );

        // sell base token(x) for quote token(y), pricea(y / x) decreases
        ICLPoolManager.SwapParams memory params = ICLPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.1 ether,
            sqrtPriceLimitX96: SQRT_RATIO_1_2
        });

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        router.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwap_succeedsWithNativeTokensIfInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        poolManager.initialize(key, SQRT_RATIO_1_1);

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Swap(key.toId(), address(router), 0, 0, SQRT_RATIO_1_2, 0, -6932, 3000, 0);

        router.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwap_succeedsWithHooksIfInitialized() public {
        MockHooks mockAddr = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(mockAddr),
            poolManager: poolManager,
            parameters: bytes32((uint256(60) << 16) | mockAddr.getHooksRegistrationBitmap())
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        poolManager.initialize(key, SQRT_RATIO_1_1);

        BalanceDelta balanceDelta;
        // create a new context to swallow up the revert
        try CLPoolManagerTest(payable(this)).tryExecute(
            address(router),
            abi.encodeWithSelector(CLPoolManagerRouter.swap.selector, key, params, testSettings, ZERO_BYTES)
        ) {
            revert("must revert");
        } catch (bytes memory result) {
            balanceDelta = abi.decode(result, (BalanceDelta));
        }

        bytes memory beforePayload =
            abi.encodeWithSelector(MockHooks.beforeSwap.selector, address(router), key, params, ZERO_BYTES);

        bytes memory afterPayload =
            abi.encodeWithSelector(MockHooks.afterSwap.selector, address(router), key, params, balanceDelta, ZERO_BYTES);

        vm.expectCall(address(mockAddr), 0, beforePayload, 1);
        vm.expectCall(address(mockAddr), 0, afterPayload, 1);
        router.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwap_failsWithIncorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32((uint256(10) << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        ICLPoolManager.SwapParams memory swapParams =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        // Fails at beforeAddLiquidity hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.swap(key, swapParams, testSettings, ZERO_BYTES);

        // Fail at afterAddLiquidity hook.
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function testSwap_succeedsWithCorrectSelectors() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32((uint256(10) << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100, salt: 0});

        ICLPoolManager.SwapParams memory swapParams =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit ICLPoolManager.Swap(key.toId(), address(router), 0, 0, SQRT_RATIO_1_2, 0, -6932, 100, 0);

        router.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function testSwap_leaveSurplusTokenInVault() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000000000000000000,
                salt: 0
            }),
            ZERO_BYTES
        );

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(router), address(0), address(this), currency1, 98);
        router.swap(key, params, testSettings, ZERO_BYTES);

        uint256 surplusTokenAmount = vault.balanceOf(address(this), currency1);
        assertEq(surplusTokenAmount, 98);
    }

    function testSwap_useSurplusTokenAsInput() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000000000000000000,
                salt: 0
            }),
            ZERO_BYTES
        );
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(router), address(0), address(this), currency1, 98);
        router.swap(key, params, testSettings, ZERO_BYTES);

        uint256 surplusTokenAmount = vault.balanceOf(address(this), currency1);
        assertEq(surplusTokenAmount, 98);

        // give permission for router to burn the surplus tokens
        vault.approve(address(router), currency0, type(uint256).max);
        vault.approve(address(router), currency1, type(uint256).max);

        // swap from currency1 to currency0 again, using surplus tokne as input
        params = ICLPoolManager.SwapParams({zeroForOne: false, amountSpecified: 25, sqrtPriceLimitX96: SQRT_RATIO_4_1});

        testSettings = CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: false});

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(router), address(router), address(0), currency1, 27);
        router.swap(key, params, testSettings, ZERO_BYTES);

        surplusTokenAmount = vault.balanceOf(address(this), currency1);
        assertEq(surplusTokenAmount, 71);
    }

    function testSwap_gas() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.swap(key, params, testSettings, ZERO_BYTES);

        params = ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("CLPoolManagerTest#swap_simple");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_withNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.swap(key, params, testSettings, ZERO_BYTES);

        params = ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("CLPoolManagerTest#swap_withNative");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_withHooks_gas() public {
        MockHooks mockHooks = new MockHooks();

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32((uint256(60) << 16) | mockHooks.getHooksRegistrationBitmap())
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.swap(key, params, testSettings, ZERO_BYTES);

        params = ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        snapStart("CLPoolManagerTest#swap_withHooks");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_leaveSurplusTokenInVault_gas() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000000000000000000,
                salt: 0
            }),
            ZERO_BYTES
        );

        snapStart("CLPoolManagerTest#swap_leaveSurplusTokenInVault");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_useSurplusTokenAsInput_gas() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: false, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000000000000000000,
                salt: 0
            }),
            ZERO_BYTES
        );
        router.swap(key, params, testSettings, ZERO_BYTES);

        uint256 surplusTokenAmount = vault.balanceOf(address(this), currency1);
        assertEq(surplusTokenAmount, 98);

        // give permission for router to burn the surplus tokens
        vault.approve(address(router), currency0, type(uint256).max);
        vault.approve(address(router), currency1, type(uint256).max);

        // swap from currency1 to currency0 again, using surplus tokne as input
        params = ICLPoolManager.SwapParams({zeroForOne: false, amountSpecified: 25, sqrtPriceLimitX96: SQRT_RATIO_4_1});

        testSettings = CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: false});

        snapStart("CLPoolManagerTest#swap_useSurplusTokenAsInput");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_againstLiq_gas() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000000000000000000,
                salt: 0
            }),
            ZERO_BYTES
        );

        router.swap(key, params, testSettings, ZERO_BYTES);

        params = ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("CLPoolManagerTest#swap_againstLiquidity");
        router.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwap_againstLiqWithNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        ICLPoolManager.SwapParams memory params =
            ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        CLPoolManagerRouter.SwapTestSettings memory testSettings =
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true});

        poolManager.initialize(key, SQRT_RATIO_1_1);
        router.modifyPosition{value: 1 ether}(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1 ether, salt: 0}),
            ZERO_BYTES
        );

        router.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);

        params = ICLPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("CLPoolManagerTest#swap_againstLiquidity");
        router.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    // **************        *************** //
    // **************  donate  *************** //
    // **************        *************** //

    function testDonateFailsIfNotInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        vm.expectRevert(abi.encodeWithSelector(CLPool.PoolNotInitialized.selector));
        router.donate(key, 100, 100, ZERO_BYTES);
    }

    function testDonateFailsIfNoLiquidity(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, sqrtPriceX96);
        vm.expectRevert(abi.encodeWithSelector(CLPool.NoLiquidityToReceiveFees.selector));
        router.donate(key, 100, 100, ZERO_BYTES);
    }

    // test successful donation if pool has liquidity
    function testDonateSucceedsWhenPoolHasLiquidity() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);
        snapStart("CLPoolManagerTest#donateBothTokens");
        router.donate(key, 100, 200, ZERO_BYTES);
        snapEnd();

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = poolManager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateSucceedsForNativeTokensWhenPoolHasLiquidity() public {
        vm.deal(address(this), 1 ether);

        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 100,
            poolManager: poolManager,
            hooks: IHooks(address(0)),
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition{value: 1}(key, params, ZERO_BYTES);
        router.donate{value: 100}(key, 100, 200, ZERO_BYTES);

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = poolManager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateFailsWithIncorrectSelectors() public {
        address hookAddr = makeAddr("hook");

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16) | impl.getHooksRegistrationBitmap())
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        // Fails at beforeDonate hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.donate(key, 100, 200, ZERO_BYTES);

        // Fail at afterDonate hook.
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        router.donate(key, 100, 200, ZERO_BYTES);
    }

    function testDonateSucceedsWithCorrectSelectors() public {
        address hookAddr = makeAddr("hook");

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16) | impl.getHooksRegistrationBitmap())
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        router.donate(key, 100, 200, ZERO_BYTES);
    }

    function testDonateSuccessWithEventEmitted() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);

        (, int24 tick,,) = poolManager.getSlot0(key.toId());

        vm.expectEmit();
        emit ICLPoolManager.Donate(key.toId(), address(router), 100, 0, tick);

        router.donate(key, 100, 0, ZERO_BYTES);
    }

    function testGasDonateOneToken() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);

        snapStart("CLPoolManagerTest#gasDonateOneToken");
        router.donate(key, 100, 0, ZERO_BYTES);
        snapEnd();
    }

    function testTake_failsWithInvalidTokensThatDoNotReturnTrueOnTransfer() public {
        NonStandardERC20 invalidToken = new NonStandardERC20(2 ** 255);
        Currency invalidCurrency = Currency.wrap(address(invalidToken));
        bool currency0Invalid = invalidCurrency < currency0;
        PoolKey memory key = PoolKey({
            currency0: currency0Invalid ? invalidCurrency : currency0,
            currency1: currency0Invalid ? currency0 : invalidCurrency,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(60) << 16)
        });

        invalidToken.approve(address(router), type(uint256).max);
        invalidToken.approve(address(router), type(uint256).max);
        MockERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);

        poolManager.initialize(key, SQRT_RATIO_1_1);
        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 1000, 0);
        router.modifyPosition(key, params, ZERO_BYTES);

        (uint256 amount0, uint256 amount1) = currency0Invalid ? (1, 0) : (0, 1);
        vm.expectRevert();
        router.take(key, amount0, amount1);

        // should not revert when non zero amount passed in for valid currency
        // assertions inside router because it takes then settles
        (amount0, amount1) = currency0Invalid ? (0, 1) : (1, 0);
        router.take(key, amount0, amount1);
    }

    function testTake_succeedsWithPoolWithLiquidity() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition(key, params, ZERO_BYTES);
        router.take(key, 1, 1); // assertions inside router because it takes then settles
    }

    function testTake_succeedsWithPoolWithLiquidityWithNativeToken() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams(-60, 60, 100, 0);
        router.modifyPosition{value: 100}(key, params, ZERO_BYTES);
        router.take{value: 1}(key, 1, 1); // assertions inside router because it takes then settles
    }

    function testSetProtocolFee_updatesProtocolFeeForInitializedPool() public {
        uint24 protocolFee = 4;

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.protocolFee(), 0);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setProtocolFeeForPool(key.toId(), protocolFee);

        vm.expectEmit(false, false, false, true);
        emit ProtocolFeeUpdated(key.toId(), protocolFee);
        vm.prank(address(feeController));
        poolManager.setProtocolFee(key, protocolFee);
    }

    function testCollectProtocolFees_initializesWithProtocolFeeIfCalled() public {
        uint24 protocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12);
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setProtocolFeeForPool(key.toId(), protocolFee);

        poolManager.initialize(key, SQRT_RATIO_1_1);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.protocolFee(), protocolFee);
    }

    function testCollectProtocolFees_ERC20_returnsAllFeesIf0IsProvidedAsParameter() public {
        // protocol fee 0.1%
        uint24 protocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12);
        uint256 expectedProtocolFees =
            uint256(10000) * ProtocolFeeLibrary.MAX_PROTOCOL_FEE / ProtocolFeeLibrary.PIPS_DENOMINATOR;

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setProtocolFeeForPool(key.toId(), protocolFee);

        poolManager.initialize(key, SQRT_RATIO_1_1);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.protocolFee(), protocolFee);

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams(-120, 120, 10 ether, 0);
        router.modifyPosition(key, params, ZERO_BYTES);
        router.swap(
            key,
            ICLPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2),
            CLPoolManagerRouter.SwapTestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(poolManager.protocolFeesAccrued(currency0), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        poolManager.collectProtocolFees(address(1), currency0, 0);
        assertEq(currency0.balanceOf(address(1)), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(currency0), 0);
    }

    function testCollectProtocolFees_nativeToken_allowsFeeControllerToAccumulateFees() public {
        // protocol fee 0.1%
        uint24 protocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12);
        uint256 expectedProtocolFees =
            uint256(10000) * ProtocolFeeLibrary.MAX_PROTOCOL_FEE / ProtocolFeeLibrary.PIPS_DENOMINATOR;
        Currency nativeCurrency = Currency.wrap(address(0));

        PoolKey memory key = PoolKey({
            currency0: nativeCurrency,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setProtocolFeeForPool(key.toId(), protocolFee);

        poolManager.initialize(key, SQRT_RATIO_1_1);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.protocolFee(), protocolFee);

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams(-120, 120, 10 ether, 0);
        router.modifyPosition{value: 10 ether}(key, params, ZERO_BYTES);
        router.swap{value: 10000}(
            key,
            ICLPoolManager.SwapParams(true, -10000, SQRT_RATIO_1_2),
            CLPoolManagerRouter.SwapTestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(poolManager.protocolFeesAccrued(nativeCurrency), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        poolManager.collectProtocolFees(address(1), nativeCurrency, expectedProtocolFees);
        assertEq(nativeCurrency.balanceOf(address(1)), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function testCollectProtocolFees_nativeToken_returnsAllFeesIf0IsProvidedAsParameter() public {
        // protocol fee 0.1%
        uint24 protocolFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE | (uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12);
        uint256 expectedProtocolFees =
            uint256(10000) * ProtocolFeeLibrary.MAX_PROTOCOL_FEE / ProtocolFeeLibrary.PIPS_DENOMINATOR;
        Currency nativeCurrency = Currency.wrap(address(0));

        PoolKey memory key = PoolKey({
            currency0: nativeCurrency,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setProtocolFeeForPool(key.toId(), protocolFee);

        poolManager.initialize(key, SQRT_RATIO_1_1);
        (CLSlot0 slot0,,,) = poolManager.pools(key.toId());
        assertEq(slot0.protocolFee(), protocolFee);

        ICLPoolManager.ModifyLiquidityParams memory params =
            ICLPoolManager.ModifyLiquidityParams(-120, 120, 10 ether, 0);
        router.modifyPosition{value: 10 ether}(key, params, ZERO_BYTES);
        router.swap{value: 10000}(
            key,
            ICLPoolManager.SwapParams(true, -10000, SQRT_RATIO_1_2),
            CLPoolManagerRouter.SwapTestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(poolManager.protocolFeesAccrued(nativeCurrency), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        poolManager.collectProtocolFees(address(1), nativeCurrency, 0);
        assertEq(nativeCurrency.balanceOf(address(1)), expectedProtocolFees);
        assertEq(poolManager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function testUpdateDynamicLPFee_FeeTooLarge() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });

        clFeeManagerHook.setFee(LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE + 1)
        );
        vm.prank(address(clFeeManagerHook));
        poolManager.updateDynamicLPFee(key, LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE + 1);
    }

    function testUpdateDynamicLPFee_FeeNotDynamic() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(3000), // 3000 = 0.3%
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10) << 16)
        });

        vm.expectRevert(IPoolManager.UnauthorizedDynamicLPFeeUpdate.selector);
        poolManager.updateDynamicLPFee(key, 3000);
    }

    function testFuzzUpdateDynamicLPFee(uint24 _swapFee) public {
        vm.assume(_swapFee < LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE);

        uint16 bitMap = 0x0010; // 0000 0000 0001 0000 (before swap call)
        clFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: bytes32(uint256((10 << 16) | clFeeManagerHook.getHooksRegistrationBitmap()))
        });

        poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);

        clFeeManagerHook.setFee(_swapFee);

        vm.expectEmit();
        emit DynamicLPFeeUpdated(key.toId(), _swapFee);

        vm.prank(address(clFeeManagerHook));
        poolManager.updateDynamicLPFee(key, _swapFee);

        (,,, uint24 swapFee) = poolManager.getSlot0(key.toId());
        assertEq(swapFee, _swapFee);
    }

    function testGasUpdateDynamicLPFee() public {
        uint24 _swapFee = LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE / 2;

        uint16 bitMap = 0x0010; // 0000 0000 0001 0000 (before swap call)
        clFeeManagerHook.setHooksRegistrationBitmap(bitMap);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: IHooks(address(clFeeManagerHook)),
            poolManager: poolManager,
            parameters: bytes32(uint256((10 << 16) | clFeeManagerHook.getHooksRegistrationBitmap()))
        });

        poolManager.initialize(key, TickMath.MIN_SQRT_RATIO);

        clFeeManagerHook.setFee(_swapFee);

        vm.expectEmit();
        emit DynamicLPFeeUpdated(key.toId(), _swapFee);

        vm.prank(address(clFeeManagerHook));
        snapStart("CLPoolManagerTest#testFuzzUpdateDynamicLPFee");
        poolManager.updateDynamicLPFee(key, _swapFee);
        snapEnd();

        (,,, uint24 swapFee) = poolManager.getSlot0(key.toId());
        assertEq(swapFee, _swapFee);
    }

    function testModifyLiquidity_Add_WhenPaused() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(0x10000))
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        // pause
        poolManager.pause();

        vm.expectRevert(ICLPoolManager.PoolPaused.selector);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 1e24,
                salt: 0
            }),
            ""
        );
    }

    function testModifyLiquidity_Remove_WhenPaused() public {
        // make sure enough balance for the test
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1e30 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1e30 ether);
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(0x10000))
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        // pre-req add liquidity
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e24, salt: 0}),
            ""
        );

        // pause
        poolManager.pause();

        // verify no revert
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1e24, salt: 0}),
            ""
        );
    }

    function testSwap_WhenPaused() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(0x10000))
        });

        poolManager.initialize(key, SQRT_RATIO_1_1);
        IERC20(Currency.unwrap(currency0)).approve(address(router), 1e10 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1e10 ether);

        // pause
        poolManager.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 0.1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );
    }

    function testDonate_WhenPaused() public {
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            poolManager: poolManager,
            parameters: bytes32(uint256(10 << 16))
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        // pause
        poolManager.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        router.donate(key, 100, 200, ZERO_BYTES);
    }

    function checkUnusedBitsAllZero(bytes32 params) internal pure returns (bool) {
        return
            (uint256(params) & (type(uint256).max << CLPoolParametersHelper.OFFSET_MOST_SIGNIFICANT_UNUSED_BITS)) == 0;
    }

    function _validateHookConfig(PoolKey memory poolKey) internal view returns (bool) {
        uint16 bitmapInParameters = poolKey.parameters.getHooksRegistrationBitmap();
        if (address(poolKey.hooks) == address(0)) {
            if (bitmapInParameters == 0 && !poolKey.fee.isDynamicLPFee()) {
                return true;
            }
            return false;
        }

        if (poolKey.hooks.getHooksRegistrationBitmap() != bitmapInParameters) {
            return false;
        }

        return true;
    }

    function _validateHookPermissionsConflict(PoolKey memory key) internal pure returns (bool) {
        if (
            key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_BEFORE_SWAP_OFFSET)
        ) {
            return false;
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_SWAP_OFFSET)
        ) {
            return false;
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_ADD_LIQUIDIY_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_ADD_LIQUIDITY_OFFSET)
        ) {
            return false;
        }

        if (
            key.parameters.hasOffsetEnabled(HOOKS_AFTER_REMOVE_LIQUIDIY_RETURNS_DELTA_OFFSET)
                && !key.parameters.hasOffsetEnabled(HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET)
        ) {
            return false;
        }
        return true;
    }

    function tryExecute(address target, bytes memory msgData) external {
        (bool success, bytes memory result) = target.call(msgData);
        if (!success) {
            return;
        }

        assembly {
            revert(add(result, 0x20), mload(result))
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
