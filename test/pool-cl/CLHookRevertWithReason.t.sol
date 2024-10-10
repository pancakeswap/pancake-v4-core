// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Vault} from "../../src/Vault.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {CLPool} from "../../src/pool-cl/libraries/CLPool.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {CLRevertHook} from "./helpers/CLRevertHook.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {BaseCLTestHook} from "./helpers/BaseCLTestHook.sol";

/// @dev make sure the revert reason is bubbled up
contract CLHookRevertWithReasonTest is Test, Deployers, TokenFixture {
    using CLPoolParametersHelper for bytes32;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLRevertHook public hook;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();

        hook = new CLRevertHook();
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
    }

    function testRevertWithNoReason() public {
        vm.expectRevert(abi.encodeWithSelector(Hooks.Wrap__FailedHookCall.selector, hook, new bytes(0)));
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }

    function testRevertWithHookNotImplemented() public {
        hook.setRevertWithHookNotImplemented(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                Hooks.Wrap__FailedHookCall.selector,
                hook,
                abi.encodeWithSelector(BaseCLTestHook.HookNotImplemented.selector)
            )
        );
        poolManager.initialize(key, SQRT_RATIO_1_1);
    }
}
