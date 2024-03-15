// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {Vault} from "../src/Vault.sol";

/**
 * forge script script/01_DeployVault.s.sol:DeployVaultScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow \
 *     --verify
 */
contract DeployVaultScript is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Vault vault = new Vault();
        console.log("Vault contract deployed at ", address(vault));

        vm.stopBroadcast();
    }
}
