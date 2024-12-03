// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {ProtocolFeeController} from "../src/ProtocolFeeController.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";

/**
 * Step 1: Set ProtocolFeeController for BinPool
 * forge script script/05b_SetProtocolFeeControllerForBinPool.s.sol:SetProtocolFeeControllerForBinPoolScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 */
contract SetProtocolFeeControllerForBinPoolScript is BaseScript {
    function run() public {
        // @dev this should be the private key of the poolManager owner instead of the deployer
        uint256 ownerPrivateKey = vm.envUint("POOL_OWNER_PRIVATE_KEY");
        vm.startBroadcast(ownerPrivateKey);

        IProtocolFees binPoolManager = IProtocolFees(getAddressFromConfig("binPoolManager"));
        console.log("binPoolManager address: ", address(binPoolManager));

        ProtocolFeeController binProtocolFeeController =
            ProtocolFeeController(getAddressFromConfig("binProtocolFeeController"));
        console.log("binProtocolFeeController address: ", address(binProtocolFeeController));

        if (binProtocolFeeController.poolManager() != address(binPoolManager)) {
            revert("PoolManager mismatch");
        }

        IProtocolFees(binPoolManager).setProtocolFeeController(
            ProtocolFeeController(getAddressFromConfig("binProtocolFeeController"))
        );

        vm.stopBroadcast();
    }
}
