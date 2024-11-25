// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {BinPoolManager} from "../src/pool-bin/BinPoolManager.sol";
import {Create3Factory} from "pancake-create3-factory/src/Create3Factory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Step 1: Deploy
 * forge script script/03_DeployBinPoolManager.s.sol:DeployBinPoolManagerScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 *
 * Step 2: Get the ABI-encoded form of the constructor arguments
 * cast abi-encode "Constructor(address)" <vault_addr>
 *
 * Step 3: Verify
 * forge verify-contract <address> BinPoolManager --watch --chain <chain_id> \
 *    --constructor-args <constructor_args_from_step2>
 */
contract DeployBinPoolManagerScript is BaseScript {
    function getDeploymentSalt() public pure override returns (bytes32) {
        return keccak256("PANCAKE-V4-CORE/BinPoolManager/0.90");
    }

    function run() public {
        Create3Factory factory = Create3Factory(getAddressFromConfig("create3Factory"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address vault = getAddressFromConfig("vault");
        console.log("vault address: ", address(vault));

        /// @dev append the vault address to the creationCode
        bytes memory creationCode = abi.encodePacked(type(BinPoolManager).creationCode, abi.encode(vault));

        /// @dev prepare the payload to transfer ownership from deployer to real owner
        bytes memory afterDeploymentExecutionPayload =
            abi.encodeWithSelector(Ownable.transferOwnership.selector, getAddressFromConfig("owner"));

        address binPoolManager = factory.deploy(
            getDeploymentSalt(), creationCode, keccak256(creationCode), 0, afterDeploymentExecutionPayload, 0
        );

        console.log("BinPoolManager contract deployed at ", binPoolManager);

        console.log("Registering BinPoolManager");
        IVault(address(vault)).registerApp(address(binPoolManager));

        vm.stopBroadcast();
    }
}
