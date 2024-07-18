//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IPoolManager} from "./IPoolManager.sol";
import {Currency} from "../types/Currency.sol";

interface IVaultToken {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    event Approval(address indexed owner, address indexed spender, Currency indexed currency, uint256 amount);

    event Transfer(address caller, address indexed from, address indexed to, Currency indexed currency, uint256 amount);

    /// @notice get the amount of owner's surplus token in vault
    /// @param owner The address you want to query the balance of
    /// @param currency The currency you want to query the balance of
    /// @return balance The balance of the specified address
    function balanceOf(address owner, Currency currency) external view returns (uint256 balance);

    /// @notice get the amount that owner has authorized for spender to use
    /// @param owner The address of the owner
    /// @param spender The address who is allowed to spend the owner's token
    /// @param currency The currency the spender is allowed to spend
    /// @return amount The amount of token the spender is allowed to spend
    function allowance(address owner, address spender, Currency currency) external view returns (uint256 amount);

    /// @notice approve spender for using user's token
    /// @param spender The address msg.sender is approving to spend the his token
    /// @param currency The currency the spender is allowed to spend
    /// @param amount The amount of token the spender is allowed to spend
    /// @return bool Whether the approval was successful or not
    function approve(address spender, Currency currency, uint256 amount) external returns (bool);

    /// @notice transfer msg.sender's token to someone else
    /// @param to The address to transfer the token to
    /// @param currency The currency to transfer
    /// @param amount The amount of token to transfer
    /// @return bool Whether the transfer was successful or not
    function transfer(address to, Currency currency, uint256 amount) external returns (bool);

    /// @notice transfer from address's token on behalf of him
    /// @param from The address to transfer the token from
    /// @param to The address to transfer the token to
    /// @param currency The currency to transfer
    /// @param amount The amount of token to transfer
    /// @return bool Whether the transfer was successful or not
    function transferFrom(address from, address to, Currency currency, uint256 amount) external returns (bool);
}
