// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {ProtocolFeeController} from "../src/ProtocolFeeController.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";

/**
 * Step 1: Set ProtocolFeeController for CLPool
 * forge script script/04b_SetProtocolFeeControllerForCLPool.s.sol:SetProtocolFeeControllerForCLPoolScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 */
contract SetProtocolFeeControllerForCLPoolScript is BaseScript {
    function run() public {
        // @dev this should be the private key of the poolManager owner instead of the deployer
        uint256 ownerPrivateKey = vm.envUint("POOL_OWNER_PRIVATE_KEY");
        vm.startBroadcast(ownerPrivateKey);

        IProtocolFees clPoolManager = IProtocolFees(getAddressFromConfig("clPoolManager"));
        console.log("clPoolManager address: ", address(clPoolManager));

        ProtocolFeeController clProtocolFeeController =
            ProtocolFeeController(getAddressFromConfig("clProtocolFeeController"));
        console.log("clProtocolFeeController address: ", address(clProtocolFeeController));

        if (clProtocolFeeController.poolManager() != address(clPoolManager)) {
            revert("PoolManager mismatch");
        }

        IProtocolFees(clPoolManager).setProtocolFeeController(
            ProtocolFeeController(getAddressFromConfig("clProtocolFeeController"))
        );

        vm.stopBroadcast();
    }
}
