// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {Exttload} from "../src/Exttload.sol";
import {ILockCallback} from "../src/interfaces/ILockCallback.sol";

contract LockerLoadable is Exttload, ILockCallback {
    bytes32 constant LOCKER_SLOT = bytes32(uint256(keccak256("SETTLEMENT_LOCKER")) - 1);
    bytes32 constant UNSETTLED_DELTAS_COUNT = bytes32(uint256(keccak256("SETTLEMENT_UNSETTLEMENTD_DELTAS_COUNT")) - 1);

    bool extLoadSingle;
    IVault vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function extLoadLockerSingle() external {
        extLoadSingle = true;
        vault.lock("0x00");
    }

    function extLoadLockerBatch() external {
        vault.lock("0x00");
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (extLoadSingle) {
            address locker1 = address(uint160(uint256(vault.exttload(LOCKER_SLOT))));
            address locker2 = vault.getLocker();
            if (locker1 != locker2) revert();
        } else {
            bytes32[] memory slots = new bytes32[](2);
            slots[0] = UNSETTLED_DELTAS_COUNT;
            slots[1] = LOCKER_SLOT;
            bytes32[] memory values = vault.exttload(slots);

            // verify unsettled delta. Potentially make the test more robust with swaps so unsettedDeltaCount is non-zero
            uint256 unsettledDelta1 = uint256(values[0]);
            uint256 unsettledDelta2 = vault.getUnsettledDeltasCount();
            if (unsettledDelta1 != unsettledDelta2) revert();

            // verify locker
            address locker1 = address(uint160(uint256(values[1])));
            address locker2 = vault.getLocker();
            if (locker1 != locker2) revert();
        }

        return "";
    }
}

contract ExttloadTest is Test, GasSnapshot {
    LockerLoadable lockerLoadable;
    IVault vault;

    function setUp() public {
        IVault vault = new Vault();
        lockerLoadable = new LockerLoadable(vault);
    }

    function testExttload_Single() public {
        lockerLoadable.extLoadLockerSingle();
    }

    function testExttload_Batch() public {
        lockerLoadable.extLoadLockerBatch();
    }
}
