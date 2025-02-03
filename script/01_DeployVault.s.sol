// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {Vault} from "../src/Vault.sol";
import {Create3Factory} from "pancake-create3-factory/src/Create3Factory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Step 1: Deploy
 * forge script script/01_DeployVault.s.sol:DeployVaultScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 *
 * Step 2: Verify there is no need for --constructor-args as there are no constructor arguments for Vault
 * forge verify-contract <address> Vault --watch --chain <chain_id>
 *
 * Step 3: Proceed to deploy contract and call vault.acceptOwnership
 */
contract DeployVaultScript is BaseScript {
    function getDeploymentSalt() public pure override returns (bytes32) {
        return keccak256("INFINITY-CORE/VAULT/0.90");
    }

    function run() public {
        Create3Factory factory = Create3Factory(getAddressFromConfig("create3Factory"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /// @dev prepare the payload to transfer ownership from deployer to real owner
        bytes memory afterDeploymentExecutionPayload =
            abi.encodeWithSelector(Ownable.transferOwnership.selector, getAddressFromConfig("poolOwner"));

        address vault = factory.deploy(
            getDeploymentSalt(),
            type(Vault).creationCode,
            keccak256(type(Vault).creationCode),
            0,
            afterDeploymentExecutionPayload,
            0
        );

        console.log("Vault contract deployed at ", vault);

        vm.stopBroadcast();
    }
}
