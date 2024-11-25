// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {CLPoolManager} from "../src/pool-cl/CLPoolManager.sol";
import {BinPoolManager} from "../src/pool-bin/BinPoolManager.sol";
import {ProtocolFeeController} from "../src/ProtocolFeeController.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {LPFeeLibrary} from "../src/libraries/LPFeeLibrary.sol";
import {TokenFixture} from "./helpers/TokenFixture.sol";
import {Constants} from "../test/pool-cl/helpers/Constants.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {CLPoolParametersHelper} from "../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {BinPoolParametersHelper} from "../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {ProtocolFeeLibrary} from "../src/libraries/ProtocolFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";

contract ProtocolFeeControllerTest is TokenFixture, Test {
    using CLPoolParametersHelper for bytes32;
    using BinPoolParametersHelper for bytes32;
    using ProtocolFeeLibrary for *;

    Vault vault;
    CLPoolManager clPoolManager;
    BinPoolManager binPoolManager;

    function setUp() public {
        vault = new Vault();
        clPoolManager = new CLPoolManager(vault);
        binPoolManager = new BinPoolManager(vault);

        initializeTokens();
    }

    function testSetProcotolFeeSplitRatio(uint256 newProtocolFeeSplitRatio) public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert();
            controller.setProtocolFeeSplitRatio(newProtocolFeeSplitRatio);
        }

        if (newProtocolFeeSplitRatio > controller.ONE_HUNDRED_PERCENT_RATIO()) {
            vm.expectRevert(ProtocolFeeController.InvliadProtocolFeeSplitRatio.selector);
            controller.setProtocolFeeSplitRatio(newProtocolFeeSplitRatio);
        } else {
            controller.setProtocolFeeSplitRatio(newProtocolFeeSplitRatio);
            assertEq(controller.protocolFeeSplitRatio(), newProtocolFeeSplitRatio);
        }
    }

    function testSetDefaultProtocolFee(PoolKey memory key, uint24 newProtocolFee) public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert();
            controller.setDefaultProtocolFee(key, newProtocolFee);
        }

        {
            // key match
            key.poolManager = IPoolManager(makeAddr("notPoolManagerAddress"));
            vm.expectRevert(ProtocolFeeController.InvalidPoolManager.selector);
            controller.setDefaultProtocolFee(key, newProtocolFee);
        }

        key.poolManager = clPoolManager;
        if (!newProtocolFee.validate()) {
            vm.expectRevert(abi.encodeWithSelector(IProtocolFees.ProtocolFeeTooLarge.selector, newProtocolFee));
            controller.setDefaultProtocolFee(key, newProtocolFee);
        } else {
            controller.setDefaultProtocolFee(key, newProtocolFee);
            assertEq(controller.defaultProtocolFees(key.toId()), newProtocolFee);
        }
    }

    function testCLPoolInitWithoutProtolFeeController(uint24 lpFee) public {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: clPoolManager,
            fee: lpFee,
            parameters: bytes32(0).setTickSpacing(10)
        });
        clPoolManager.initialize(key, Constants.SQRT_RATIO_1_1);

        (,, uint24 actualProtocolFee, uint24 actualLpFee) = clPoolManager.getSlot0(key.toId());

        assertEq(actualLpFee, lpFee);
        assertEq(actualProtocolFee, 0);
    }

    function testCLPoolInitWithProtolFeeControllerFuzz(uint24 lpFee, uint256 newProtocolFeeRatio) public {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.ONE_HUNDRED_PERCENT_FEE));
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));
        newProtocolFeeRatio = bound(newProtocolFeeRatio, 0, controller.ONE_HUNDRED_PERCENT_RATIO());

        clPoolManager.setProtocolFeeController(controller);
        controller.setProtocolFeeSplitRatio(newProtocolFeeRatio);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: clPoolManager,
            fee: lpFee,
            parameters: bytes32(0).setTickSpacing(10)
        });
        clPoolManager.initialize(key, Constants.SQRT_RATIO_1_1);

        (,, uint24 actualProtocolFee, uint24 actualLpFee) = clPoolManager.getSlot0(key.toId());

        assertEq(actualLpFee, lpFee);

        // under default rule protocol fee must be equal for both directions
        uint16 protocolFeeZeroForOne = actualProtocolFee.getZeroForOneFee();
        uint16 protocolFeeOneForZero = actualProtocolFee.getOneForZeroFee();
        assertEq(protocolFeeOneForZero, protocolFeeZeroForOne);

        // protocol fee should always be no more than the cap
        assertLe(protocolFeeOneForZero, ProtocolFeeLibrary.MAX_PROTOCOL_FEE);

        if (protocolFeeOneForZero == ProtocolFeeLibrary.MAX_PROTOCOL_FEE) {
            // for example, given splitRatio=33% then lpFee=0.81538274% is the threshold that will make the protocol fee 0.4%
            assertGe(lpFee, _calculateLPFeeThreshold(controller));
        } else {
            // protocol fee should be the given ratio of the total fee
            uint24 totalFee = protocolFeeZeroForOne.calculateSwapFee(actualLpFee);
            assertApproxEqAbs(
                totalFee * controller.protocolFeeSplitRatio() / controller.ONE_HUNDRED_PERCENT_RATIO(),
                protocolFeeZeroForOne,
                // keeping the error within 0.01% (can't avoid due to precision loss)
                100
            );
        }
    }

    function testProtocolFee(PoolKey memory key, uint24 newProtocolFee) public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert();
            controller.setProtocolFee(key, newProtocolFee);
        }

        {
            // key match
            key.poolManager = IPoolManager(makeAddr("notPoolManagerAddress"));
            vm.expectRevert(ProtocolFeeController.InvalidPoolManager.selector);
            controller.setDefaultProtocolFee(key, newProtocolFee);
        }

        key.poolManager = clPoolManager;
        if (!newProtocolFee.validate()) {
            vm.expectRevert(abi.encodeWithSelector(IProtocolFees.ProtocolFeeTooLarge.selector, newProtocolFee));
            controller.setDefaultProtocolFee(key, newProtocolFee);
        } else {
            controller.setDefaultProtocolFee(key, newProtocolFee);
            assertEq(controller.defaultProtocolFees(key.toId()), newProtocolFee);
        }
    }

    function _calculateLPFeeThreshold(ProtocolFeeController controller) internal view returns (uint24) {
        return uint24(
            (
                (controller.ONE_HUNDRED_PERCENT_RATIO() / controller.protocolFeeSplitRatio() - 1)
                    * ProtocolFeeLibrary.MAX_PROTOCOL_FEE
            ) / (controller.ONE_HUNDRED_PERCENT_RATIO() - ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
        );
    }
}
