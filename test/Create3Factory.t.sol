// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/Test.sol";
import {CREATE3} from "solmate/src/utils/Create3.sol";
import {Vault} from "../src/Vault.sol";
import {CLPoolManager} from "../src/pool-cl/CLPoolManager.sol";

/// @notice Through the use of solmate create3, deploy contracts with deterministic addresses
contract Create3Factory {
    /// @notice deploy a contract with a deterministic address based on `salt + msg.sender (deployer)`
    /// @dev this means that two contract with different creationCode can be deployed on the same address on different chains
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        return CREATE3.deploy(salt, creationCode, msg.value);
    }

    /// @notice get the deployed address of a contract with a deterministic address based on `salt + deployer`
    function getDeployed(address deployer, bytes32 salt) public view returns (address deployed) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(deployer, salt));
        return CREATE3.getDeployed(salt);
    }
}

contract Create3FactoryTest is Test, GasSnapshot {
    Create3Factory create3Factory;
    Vault vault;
    CLPoolManager clPoolManager;

    function setUp() public {
        create3Factory = new Create3Factory();
    }

    function test_deploy_NonDeterministic() public {
        // deploy
        vault = new Vault();
        snapLastCall("Create3FactoryTest#test_deploy_NonDeterministic");
    }

    /// @dev showcase a need to pass in owner address
    function test_Create3_Deploy() public {
        // deploy
        bytes memory creationCode = type(Vault).creationCode;
        bytes32 salt = bytes32(uint256(0x1234));
        address deployed = create3Factory.deploy(salt, creationCode);
        snapLastCall("Create3FactoryTest#test_deploy");

        vault = Vault(deployed);
        // note equal as owner is the proxy contract, not factory
        assertNotEq(vault.owner(), address(create3Factory));
    }

    function test_Create3_Deploy_CLPoolManager() public {
        // deploy vault
        bytes memory vaultCreationCode = type(Vault).creationCode;
        bytes32 vaultSalt = bytes32(uint256(0x1234));
        address deployedVault = create3Factory.deploy(vaultSalt, vaultCreationCode);
        vault = Vault(deployedVault);

        // deploy CLPoolManager
        bytes memory pmCreationCode = type(CLPoolManager).creationCode;
        bytes memory pmConstructorArgs = abi.encode(deployedVault);
        bytes memory pmCreationcodeWithArgs = abi.encodePacked(pmCreationCode, pmConstructorArgs);
        bytes32 pmSalt = bytes32(uint256(0x12345));
        address deployedCLPoolManager = create3Factory.deploy(pmSalt, pmCreationcodeWithArgs);
        clPoolManager = CLPoolManager(deployedVault);
    }
}
