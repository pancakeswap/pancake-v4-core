// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {BinPoolManager} from "../../src/pool-bin/BinPoolManager.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {BinRevertHook} from "./helpers/BinRevertHook.sol";
import {BaseBinTestHook} from "./helpers/BaseBinTestHook.sol";

/// @dev make sure the revert reason is bubbled up
contract BinHookRevertWithReasonTest is Test {
    using BinPoolParametersHelper for bytes32;

    Vault public vault;
    BinPoolManager public poolManager;
    BinRevertHook public hook;

    uint24 activeId = 2 ** 23; // where token0 and token1 price is the same

    PoolKey key;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        vault = new Vault();
        poolManager = new BinPoolManager(vault);
        vault.registerApp(address(poolManager));

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        hook = new BinRevertHook();

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: uint24(3000), // 3000 = 0.3%
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setBinStep(10)
        });
    }

    function testRevertWithNoReason() public {
        vm.expectRevert(abi.encodeWithSelector(Hooks.Wrap__FailedHookCall.selector, hook, new bytes(0)));
        poolManager.initialize(key, activeId, abi.encode(false));
    }

    function testRevertWithHookNotImplemented() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Hooks.Wrap__FailedHookCall.selector,
                hook,
                abi.encodeWithSelector(BaseBinTestHook.HookNotImplemented.selector)
            )
        );
        poolManager.initialize(key, activeId, abi.encode(true));
    }
}
