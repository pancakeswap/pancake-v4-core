//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHooks {
    function getHooksRegistrationBitmap() external view returns (uint16);
}
