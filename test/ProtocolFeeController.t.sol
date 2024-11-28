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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CLPoolManagerRouter} from "../test/pool-cl/helpers/CLPoolManagerRouter.sol";
import {ICLPoolManager} from "../src/pool-cl/interfaces/ICLPoolManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "../src/types/Currency.sol";
import {TickMath} from "../src/pool-cl/libraries/TickMath.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";

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
        vault.registerApp(address(clPoolManager));
        vault.registerApp(address(binPoolManager));

        initializeTokens();
    }

    function testOwnerTransfer() public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));
        // starts with address(this) as owner
        assertEq(controller.owner(), address(this));

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("someone")));
            controller.transferOwnership(makeAddr("newOwner"));
        }

        controller.transferOwnership(makeAddr("newOwner"));

        // still address(this) as owner before new owner accept
        assertEq(controller.pendingOwner(), makeAddr("newOwner"));
        assertEq(controller.owner(), address(this));

        {
            // must from pending owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("someone")));
            controller.acceptOwnership();
        }

        vm.prank(makeAddr("newOwner"));
        controller.acceptOwnership();
        assertEq(controller.owner(), makeAddr("newOwner"));
    }

    function testSetProcotolFeeSplitRatio(uint256 newProtocolFeeSplitRatio) public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("someone")));
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

    function testSetProtocolFeeForCLPool(uint24 newProtocolFee) public {
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));
        clPoolManager.setProtocolFeeController(controller);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: clPoolManager,
            fee: 3000,
            parameters: bytes32(0).setTickSpacing(10)
        });
        clPoolManager.initialize(key, Constants.SQRT_RATIO_1_1);

        {
            // must from owner
            vm.prank(makeAddr("someone"));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("someone")));
            controller.setProtocolFee(key, newProtocolFee);
        }

        {
            // key match
            key.poolManager = IPoolManager(makeAddr("notPoolManagerAddress"));
            vm.expectRevert(ProtocolFeeController.InvalidPoolManager.selector);
            controller.setProtocolFee(key, newProtocolFee);
        }

        key.poolManager = clPoolManager;
        if (!newProtocolFee.validate()) {
            vm.expectRevert(abi.encodeWithSelector(IProtocolFees.ProtocolFeeTooLarge.selector, newProtocolFee));
            controller.setProtocolFee(key, newProtocolFee);
        } else {
            controller.setProtocolFee(key, newProtocolFee);

            (,, uint24 actualProtocolFee,) = clPoolManager.getSlot0(key.toId());
            assertEq(actualProtocolFee, newProtocolFee);
        }
    }

    function testCollectProtocolFeeForCLPool() public {
        // init protocol fee controller and bind it to clPoolManager
        ProtocolFeeController controller = new ProtocolFeeController(address(clPoolManager));
        clPoolManager.setProtocolFeeController(controller);

        // init pool with protocol fee controller
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: clPoolManager,
            fee: 2000,
            parameters: bytes32(0).setTickSpacing(10)
        });
        clPoolManager.initialize(key, Constants.SQRT_RATIO_1_1);

        (,, uint24 actualProtocolFee,) = clPoolManager.getSlot0(key.toId());

        // add some liquidity
        CLPoolManagerRouter router = new CLPoolManagerRouter(vault, clPoolManager);
        IERC20(Currency.unwrap(currency0)).approve(address(router), 10000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 10000 ether);
        router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1000000 ether, salt: 0}),
            ""
        );

        // swap to generate protocol fee
        // by default splitRatio=33.33% if lpFee is 0.2% then protocol fee should be roughly 0.1%
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -100 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );

        assertEq(
            clPoolManager.protocolFeesAccrued(currency0),
            100 ether * uint256(actualProtocolFee >> 12) / controller.ONE_HUNDRED_PERCENT_RATIO()
        );

        // check lp fee is twice the protocol fee
        (, BalanceDelta accumulatedLPFee) = router.modifyPosition(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: -10,
                tickUpper: 10,
                liquidityDelta: -1000000 ether,
                salt: 0
            }),
            ""
        );

        // allow 5% error
        assertApproxEqAbs(
            clPoolManager.protocolFeesAccrued(currency0) * 2,
            uint256(int256(accumulatedLPFee.amount0())),
            clPoolManager.protocolFeesAccrued(currency0) * 2 / 20
        );

        // collect protocol fee
        {
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("someone")));
            vm.prank(makeAddr("someone"));
            controller.collectProtocolFee(makeAddr("recipient"), currency0, 0);
        }

        // collect half
        uint256 protocolFeeAmount = clPoolManager.protocolFeesAccrued(currency0);
        controller.collectProtocolFee(makeAddr("recipient"), currency0, protocolFeeAmount / 2);

        assertEq(clPoolManager.protocolFeesAccrued(currency0), protocolFeeAmount / 2);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(makeAddr("recipient")), protocolFeeAmount / 2);

        // collect the rest
        controller.collectProtocolFee(makeAddr("recipient"), currency0, 0);
        assertEq(clPoolManager.protocolFeesAccrued(currency0), 0);
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(makeAddr("recipient")), protocolFeeAmount);
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
