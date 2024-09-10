// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BaseScript} from "./BaseScript.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {BinPoolManager} from "../src/pool-bin/BinPoolManager.sol";

/**
 * forge script script/03_DeployBinPoolManager.s.sol:DeployBinPoolManagerScript -vvv \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow \
 *     --verify
 */
contract DeployBinPoolManagerScript is BaseScript {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address vault = getAddressFromConfig("vault");
        console.log("vault address: ", address(vault));

        BinPoolManager binPoolManager = new BinPoolManager(IVault(address(vault)));
        console.log("BinPoolManager contract deployed at ", address(binPoolManager));

        console.log("Registering BinPoolManager");
        IVault(address(vault)).registerApp(address(binPoolManager));

        vm.stopBroadcast();
    }
}
