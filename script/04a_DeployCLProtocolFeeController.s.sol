// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {ProtocolFeeController} from "../src/ProtocolFeeController.sol";
import {Create3Factory} from "pancake-create3-factory/src/Create3Factory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Step 1: Deploy
 * forge script script/04a_DeployCLProtocolFeeController.s.sol:DeployCLProtocolFeeControllerScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 *
 * Step 2: Get the ABI-encoded form of the constructor arguments
 * cast abi-encode "Constructor(address)" <clPoolManager_addr>
 *
 * Step 3: Verify
 * forge verify-contract <address> ProtocolFeeController --watch --chain <chain_id> \
 *    --constructor-args <constructor_args_from_step2>
 *
 * Step 4: Proceed to deploy contract and call protocolFeeController.acceptOwnership
 */
contract DeployCLProtocolFeeControllerScript is BaseScript {
    function getDeploymentSalt() public pure override returns (bytes32) {
        return keccak256("PANCAKE-V4-CORE/CLProtocolFeeController/0.91");
    }

    function run() public {
        Create3Factory factory = Create3Factory(getAddressFromConfig("create3Factory"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address clPoolManager = getAddressFromConfig("clPoolManager");
        console.log("clPoolManager address: ", address(clPoolManager));

        /// @dev append the clPoolManager address to the creationCode
        bytes memory creationCode =
            abi.encodePacked(type(ProtocolFeeController).creationCode, abi.encode(clPoolManager));

        /// @dev prepare the payload to transfer ownership from deployer to real owner
        bytes memory afterDeploymentExecutionPayload = abi.encodeWithSelector(
            Ownable.transferOwnership.selector, getAddressFromConfig("protocolFeeControllerOwner")
        );

        address clProtocolFeeController = factory.deploy(
            getDeploymentSalt(), creationCode, keccak256(creationCode), 0, afterDeploymentExecutionPayload, 0
        );

        console.log("CLProtocolFeeController contract deployed at ", clProtocolFeeController);

        vm.stopBroadcast();
    }
}
