// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/Test.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Vault} from "../src/Vault.sol";
import {CLPoolManager} from "../src/pool-cl/CLPoolManager.sol";

/// @notice Through the use of solmate create3, deploy contracts with deterministic addresses
contract Create2Factory {
    function deploy(bytes32 salt, bytes memory creationCode) public payable returns (address deployed) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        return Create2.deploy(msg.value, salt, creationCode);
    }

    function getDeployed(address deployer, bytes32 salt, bytes32 bytecodeHash) public view returns (address addr) {
        // hash salt with the deployer address to give each deployer its own namespace
        salt = keccak256(abi.encodePacked(deployer, salt));

        return Create2.computeAddress(salt, bytecodeHash);
    }

    /// @notice execute a call on a deployed contract
    /// @dev if contract uses Ownable(msg.sender) - it would mean the owner is Create2Factory, so a call is required
    function execute(bytes32 salt, bytes32 bytecodeHash, bytes calldata data) external {
        address target = getDeployed(msg.sender, salt, bytecodeHash);
        (bool success,) = target.call(data);
        require(success, "Create2Factory: failed execute call");
    }
}

contract Create2FactoryTest is Test, GasSnapshot {
    Create2Factory create2Factory;
    Vault vault;
    CLPoolManager clPoolManager;

    function setUp() public {
        create2Factory = new Create2Factory();
    }

    function test_deploy_NonDeterministic() public {
        // deploy
        vault = new Vault();
        snapLastCall("Create2FactoryTest#test_deploy_NonDeterministic");
    }

    function test_Create2_Deploy() public {
        // deploy
        bytes memory creationCode = type(Vault).creationCode;
        bytes32 salt = bytes32(uint256(0x1234));
        address deployed = create2Factory.deploy(salt, creationCode);
        snapLastCall("Create2FactoryTest#test_deploy");

        vault = Vault(deployed);
        assertEq(vault.owner(), address(create2Factory));
    }

    function test_Create2_GetDeployed() public {
        // deploy
        bytes memory creationCode = type(Vault).creationCode;
        bytes32 salt = bytes32(uint256(0x1234));
        address deployed = create2Factory.deploy(salt, creationCode);

        // get deployed
        address getDeployed = create2Factory.getDeployed(address(this), salt, keccak256(creationCode));

        // assert
        assertEq(deployed, getDeployed);
    }

    function test_Create2_Execute() public {
        // pre-req: deploy vault
        bytes memory creationCode = type(Vault).creationCode;
        bytes32 salt = bytes32(uint256(0x1234));
        address deployed = create2Factory.deploy(salt, creationCode);
        vault = Vault(deployed);
        assertEq(vault.owner(), address(create2Factory));

        address alice = makeAddr("alice");
        bytes32 bytecodeHash = keccak256(creationCode);
        bytes memory data = abi.encodeWithSignature("transferOwnership(address)", alice);
        create2Factory.execute(salt, bytecodeHash, data);
        assertEq(vault.owner(), alice);
    }

    function test_Create2_Execute_FrontRun() public {
        // pre-req: deploy vault
        bytes memory creationCode = type(Vault).creationCode;
        bytes32 salt = bytes32(uint256(0x1234));
        address deployed = create2Factory.deploy(salt, creationCode);
        vault = Vault(deployed);
        assertEq(vault.owner(), address(create2Factory));

        // assume someone front-runs the transferOwnership call
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        bytes32 bytecodeHash = keccak256(abi.encodePacked(creationCode));
        bytes memory data = abi.encodeWithSignature("transferOwnership(address)", alice);
        create2Factory.execute(salt, bytecodeHash, data);
        assertEq(vault.owner(), address(create2Factory));
    }
}
