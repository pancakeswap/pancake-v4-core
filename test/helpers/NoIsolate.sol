// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract NoIsolate {
    modifier noIsolate() {
        if (msg.sender != address(this)) {
            (bool success,) = address(this).call(msg.data);
            require(success);
        } else {
            _;
        }
    }
}
