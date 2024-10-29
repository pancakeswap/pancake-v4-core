// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {CLPoolManager} from "../src/pool-cl/CLPoolManager.sol";
import {Create3Factory} from "pancake-create3-factory/src/Create3Factory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Step1:
 * forge script script/02_DeployCLPoolManager.s.sol:DeployCLPoolManagerScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 *
 * Step2:
 * # Get the ABI-encoded form of the constructor arguments
 * cast abi-encode "CLPoolManager(address)" <vault_addr>
 *
 * Step3:
 * forge verify-contract <address> CLPoolManager --watch --chain <chain_id> \
 *     --constructor-args <constructor_args_in_ABI-encoded_form>
 */
contract DeployCLPoolManagerScript is BaseScript {
    function getDeploymentSalt() public pure override returns (bytes32) {
        return keccak256("PANCAKE-V4-CORE/CLPoolManager/1.0");
    }

    function run() public {
        Create3Factory factory = Create3Factory(getAddressFromConfig("create3Factory"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address vault = getAddressFromConfig("vault");
        console.log("vault address: ", address(vault));

        /// @dev append the vault address to the creationCode
        bytes memory creationCode = abi.encodePacked(type(CLPoolManager).creationCode, abi.encode(vault));

        /// @dev prepare the payload to transfer ownership from deployer to real owner
        bytes memory afterDeploymentExecutionPayload =
            abi.encodeWithSelector(Ownable.transferOwnership.selector, getAddressFromConfig("owner"));

        address clPoolManager = factory.deploy(
            getDeploymentSalt(), creationCode, keccak256(creationCode), 0, afterDeploymentExecutionPayload, 0
        );
        console.log("CLPoolManager contract deployed at ", clPoolManager);

        console.log("Registering CLPoolManager");
        IVault(address(vault)).registerApp(address(clPoolManager));

        vm.stopBroadcast();
    }
}
