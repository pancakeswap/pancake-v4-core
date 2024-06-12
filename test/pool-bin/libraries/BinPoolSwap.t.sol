// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {IHooks} from "../../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../../src/interfaces/IPoolManager.sol";
import {IBinPoolManager} from "../../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {MockVault} from "../../../src/test/MockVault.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../../../src/types/PoolId.sol";
import {BinPoolManager} from "../../../src/pool-bin/BinPoolManager.sol";
import {BinPool} from "../../../src/pool-bin/libraries/BinPool.sol";
import {PackedUint128Math} from "../../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {SafeCast} from "../../../src/pool-bin/libraries/math/SafeCast.sol";
import {BinPoolParametersHelper} from "../../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinTestHelper} from "../helpers/BinTestHelper.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {MockProtocolFeeController} from "../../../src/test/fee/MockProtocolFeeController.sol";

import {console2} from "forge-std/console2.sol";

contract BinPoolSwapTest is BinTestHelper {
    using PoolIdLibrary for PoolKey;
    using PackedUint128Math for bytes32;
    using BinPoolParametersHelper for bytes32;
    using SafeCast for uint256;

    MockVault public vault;
    BinPoolManager public poolManager;

    uint24 immutable activeId = ID_ONE;

    PoolKey key;
    PoolId poolId;
    bytes32 poolParam;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vault = new MockVault();
        poolManager = new BinPoolManager(IVault(address(vault)), 500000);

        poolParam = poolParam.setBinStep(10);
        key = PoolKey({
            currency0: Currency.wrap(makeAddr("token0")),
            currency1: Currency.wrap(makeAddr("token1")),
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(3000),
            parameters: poolParam // binStep
        });
        poolId = key.toId();
    }

    function test_SwapSingleBinWithProtocolFee() public {
        // Pre-req: set protocol fee at 0.1%
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 1000);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to active bin
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidityToBin(key, poolManager, bob, activeId, 1e18, 1e18, 1e18, 1e18, "");

        // Swap and verify protocol fee is 0.1%
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
        poolManager.swap(key, true, 1e18, "");

        // total fee should be 0.1% of 1e18
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 1e18 * 0.001);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_SwapMultipleBinWithProtocolFee() public {
        // Pre-req: set protocol fee at 0.1%
        MockProtocolFeeController feeController = new MockProtocolFeeController();
        uint24 protocolFee = _getSwapFee(1000, 1000); // 0.1%
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        // add 1 ether on each side to 10 bins
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 10, 10);

        // Swap and verify protocol fee is 0.1%
        assertEq(poolManager.protocolFeesAccrued(key.currency0), 0);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
        poolManager.swap(key, true, 1e18, "");

        // total fee should be 0.1% of 1e18. add 0.1% for rounding
        assertApproxEqRel(poolManager.protocolFeesAccrued(key.currency0), 1e18 * 0.001, 0.001e18);
        assertEq(poolManager.protocolFeesAccrued(key.currency1), 0);
    }

    function test_revert_SwapInsufficientAmountIn() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 0;

        vm.expectRevert(IBinPoolManager.InsufficientAmountIn.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(IBinPoolManager.InsufficientAmountIn.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function test_revert_SwapInsufficientAmountOut() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        uint128 amountIn = 1;

        vm.expectRevert(BinPool.BinPool__InsufficientAmountOut.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(BinPool.BinPool__InsufficientAmountOut.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function test_revert_SwapOutOfLiquidity() external {
        // Add liquidity of 1e18 on each side
        poolManager.initialize(key, activeId, new bytes(0));
        addLiquidity(key, poolManager, bob, activeId, 1e18, 1e18, 50, 50);

        // pool only have 1e18 token0, 1e18 token1
        uint128 amountIn = 2e18;

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, true, amountIn, "0x");

        vm.expectRevert(BinPool.BinPool__OutOfLiquidity.selector);
        poolManager.swap(key, false, amountIn, "0x");
    }

    function _getSwapFee(uint24 fee0, uint24 fee1) internal pure returns (uint24) {
        return fee0 + (fee1 << 12);
    }
}
