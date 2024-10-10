// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "solmate/src/test/utils/mocks/MockERC20.sol";
import "../src/test/MockFeePoolManager.sol";
import "../src/test/fee/MockFeeManagerHook.sol";
import {
    MockProtocolFeeController,
    RevertingMockProtocolFeeController,
    OutOfBoundsMockProtocolFeeController,
    OverflowMockProtocolFeeController,
    InvalidReturnSizeMockProtocolFeeController
} from "../src/test/fee/MockProtocolFeeController.sol";
import "../src/test/MockVault.sol";
import "../src/ProtocolFees.sol";
import "../src/interfaces/IProtocolFees.sol";
import "../src/interfaces/IVault.sol";
import "../src/interfaces/IPoolManager.sol";
import "../src/interfaces/IHooks.sol";
import "../src/libraries/LPFeeLibrary.sol";

contract ProtocolFeesTest is Test {
    MockFeePoolManager poolManager;
    MockProtocolFeeController feeController;
    RevertingMockProtocolFeeController revertingFeeController;
    OutOfBoundsMockProtocolFeeController outOfBoundsFeeController;
    OverflowMockProtocolFeeController overflowFeeController;
    InvalidReturnSizeMockProtocolFeeController invalidReturnSizeFeeController;
    MockFeeManagerHook mockFeeManagerHook;

    MockVault vault;
    PoolKey key;

    address alice = makeAddr("alice");
    MockERC20 token0;
    MockERC20 token1;

    function setUp() public {
        vault = new MockVault();
        poolManager = new MockFeePoolManager(IVault(address(vault)), 500_000);
        feeController = new MockProtocolFeeController();
        revertingFeeController = new RevertingMockProtocolFeeController();
        outOfBoundsFeeController = new OutOfBoundsMockProtocolFeeController();
        overflowFeeController = new OverflowMockProtocolFeeController();
        invalidReturnSizeFeeController = new InvalidReturnSizeMockProtocolFeeController();
        mockFeeManagerHook = new MockFeeManagerHook();

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManager)),
            fee: uint24(0), // fee not used in the setup
            parameters: 0x00
        });
    }

    function testSetProtocolFeeController() public {
        vm.expectEmit();
        emit IProtocolFees.ProtocolFeeControllerUpdated(address(feeController));

        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        assertEq(address(poolManager.protocolFeeController()), address(feeController));
    }

    function testSwap_NoProtocolFee() public {
        poolManager.initialize(key);

        (uint256 protocolFee0, uint256 protocolFee1) = poolManager.swap(key, 1e18, 1e18);
        assertEq(protocolFee0, 0);
        assertEq(protocolFee1, 0);
    }

    function testInit_WhenFeeController_ProtocolFeeCannotBeFetched() public {
        MockFeePoolManager poolManagerWithLowControllerGasLimit =
            new MockFeePoolManager(IVault(address(vault)), 5000_000);
        PoolKey memory _key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            hooks: IHooks(address(0)),
            poolManager: IPoolManager(address(poolManagerWithLowControllerGasLimit)),
            fee: uint24(0), // fee not used in the setup
            parameters: 0x00
        });
        poolManagerWithLowControllerGasLimit.setProtocolFeeController(feeController);

        vm.expectRevert(IProtocolFees.ProtocolFeeCannotBeFetched.selector);
        poolManagerWithLowControllerGasLimit.initialize{gas: 2000_000}(_key);
    }

    function testInit_WhenFeeControllerRevert() public {
        poolManager.setProtocolFeeController(revertingFeeController);
        poolManager.initialize(key);

        assertEq(poolManager.getProtocolFee(key), 0);
    }

    function testInit_WhenFeeControllerOutOfBound() public {
        poolManager.setProtocolFeeController(outOfBoundsFeeController);
        assertEq(address(poolManager.protocolFeeController()), address(outOfBoundsFeeController));
        poolManager.initialize(key);

        assertEq(poolManager.getProtocolFee(key), 0);
    }

    function testInit_WhenFeeControllerOverflow() public {
        poolManager.setProtocolFeeController(overflowFeeController);
        assertEq(address(poolManager.protocolFeeController()), address(overflowFeeController));
        poolManager.initialize(key);

        assertEq(poolManager.getProtocolFee(key), 0);
    }

    function testInit_WhenFeeControllerInvalidReturnSize() public {
        poolManager.setProtocolFeeController(invalidReturnSizeFeeController);
        assertEq(address(poolManager.protocolFeeController()), address(invalidReturnSizeFeeController));
        poolManager.initialize(key);

        assertEq(poolManager.getProtocolFee(key), 0);
    }

    function testInitFuzz(uint24 fee) public {
        poolManager.setProtocolFeeController(feeController);

        vm.mockCall(
            address(feeController), abi.encodeCall(IProtocolFeeController.protocolFeeForPool, key), abi.encode(fee)
        );

        poolManager.initialize(key);

        if (fee != 0) {
            uint24 fee0 = fee % 4096;
            uint24 fee1 = fee >> 12;

            if (fee0 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE || fee1 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
                // invalid fee, fallback to 0
                assertEq(poolManager.getProtocolFee(key), 0);
            } else {
                assertEq(poolManager.getProtocolFee(key), fee);
            }
        }
    }

    function testSetProtocolFee() public {
        poolManager.initialize(key);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        assertEq(poolManager.getProtocolFee(key), 0);

        {
            uint24 protocolFee = _buildProtocolFee(100, 100);
            vm.prank(address(feeController));
            poolManager.setProtocolFee(key, protocolFee);
            assertEq(poolManager.getProtocolFee(key), protocolFee);
        }

        {
            vm.expectRevert(IProtocolFees.InvalidCaller.selector);
            uint24 protocolFee = _buildProtocolFee(100, 100);
            poolManager.setProtocolFee(key, protocolFee);
        }

        {
            uint24 protocolFee = _buildProtocolFee(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1, 100);
            vm.expectRevert(abi.encodeWithSelector(IProtocolFees.ProtocolFeeTooLarge.selector, protocolFee));
            vm.prank(address(feeController));
            poolManager.setProtocolFee(key, protocolFee);
        }
    }

    function testSwap_OnlyProtocolFee() public {
        // set protocolFee as 0.1% of fee
        uint24 protocolFee = _buildProtocolFee(ProtocolFeeLibrary.MAX_PROTOCOL_FEE, ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));

        poolManager.initialize(key);
        (uint256 protocolFee0, uint256 protocolFee1) = poolManager.swap(key, 1e18, 1e18);
        assertEq(protocolFee0, 1e15);
        assertEq(protocolFee1, 1e15);
    }

    function test_CollectProtocolFee_OnlyFeeController() public {
        // random user
        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        vm.prank(address(alice));
        poolManager.collectProtocolFees(alice, Currency.wrap(address(token0)), 1e18);

        // owner
        address pmOwner = poolManager.owner();
        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        vm.prank(pmOwner);
        poolManager.collectProtocolFees(alice, Currency.wrap(address(token0)), 1e18);
    }

    function test_CollectProtocolFee() public {
        // set protocolFee as 0.1% of fee
        uint24 protocolFee = _buildProtocolFee(ProtocolFeeLibrary.MAX_PROTOCOL_FEE, ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
        feeController.setProtocolFeeForPool(key, protocolFee);
        poolManager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        poolManager.initialize(key);
        (uint256 protocolFee0, uint256 protocolFee1) = poolManager.swap(key, 1e18, 1e18);
        assertEq(protocolFee0, 1e15);
        assertEq(protocolFee1, 1e15);

        // send some token to vault as poolManager.swap doesn't have tokens
        token0.mint(address(vault), 1e15);
        token1.mint(address(vault), 1e15);

        // before collect
        assertEq(token0.balanceOf(alice), 0);
        assertEq(token1.balanceOf(alice), 0);
        assertEq(token0.balanceOf(address(vault)), 1e15);
        assertEq(token1.balanceOf(address(vault)), 1e15);

        // collect
        vm.startPrank(address(feeController));
        poolManager.collectProtocolFees(alice, Currency.wrap(address(token0)), 1e15);
        poolManager.collectProtocolFees(alice, Currency.wrap(address(token1)), 1e15);

        // after collect
        assertEq(token0.balanceOf(alice), 1e15);
        assertEq(token1.balanceOf(alice), 1e15);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
    }

    function _buildProtocolFee(uint24 fee0, uint24 fee1) public pure returns (uint24) {
        // max fee is 1000 pips = 0.1%
        return fee0 + (fee1 << 12);
    }
}
