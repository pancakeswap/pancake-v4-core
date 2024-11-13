//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "../../types/Currency.sol";
import {IProtocolFees} from "../../interfaces/IProtocolFees.sol";
import {PoolId} from "../../types/PoolId.sol";
import {PoolKey} from "../../types/PoolKey.sol";
import {BalanceDelta} from "../../types/BalanceDelta.sol";
import {IPoolManager} from "../../interfaces/IPoolManager.sol";
import {IExtsload} from "../../interfaces/IExtsload.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {BinPosition, BinPool} from "../libraries/BinPool.sol";

interface IBinPoolManager is IProtocolFees, IPoolManager, IExtsload {
    /// @notice PoolManagerMismatch is thrown when pool manager specified in the pool key does not match current contract
    error PoolManagerMismatch();

    /// @notice Pool binStep cannot be lesser than 1. Otherwise there will be no price jump between bin
    error BinStepTooSmall(uint16 binStep);

    /// @notice Pool binstep cannot be greater than the limit set at maxBinStep
    error BinStepTooLarge(uint16 binStep);

    /// @notice Error thrown when owner set max bin step too small
    error MaxBinStepTooSmall(uint16 maxBinStep);

    /// @notice Error thrown when bin has insufficient shares to accept donation
    error InsufficientBinShareForDonate(uint256 shares);

    /// @notice Error thrown when amount specified is 0 in swap
    error AmountSpecifiedIsZero();

    /// @notice Returns the constant representing the max bin step
    /// @return maxBinStep a value of 100 would represent a 1% price jump between bin (limit can be raised by owner)
    function maxBinStep() external view returns (uint16);

    /// @notice Returns the constant representing the min bin step
    /// @dev 1 would represent a 0.01% price jump between bin
    function MIN_BIN_STEP() external view returns (uint16);

    /// @notice min share in bin before donate is allowed in current bin
    function minBinShareForDonate() external view returns (uint256);

    /// @notice Emitted when a new pool is initialized
    /// @param id The abi encoded hash of the pool key struct for the new pool
    /// @param currency0 The first currency of the pool by address sort order
    /// @param currency1 The second currency of the pool by address sort order
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    /// @param fee The lp fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param parameters Includes hooks callback bitmap and binStep
    /// @param activeId The id of active bin on initialization
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        IHooks hooks,
        uint24 fee,
        bytes32 parameters,
        uint24 activeId
    );

    /// @notice Emitted for swaps between currency0 and currency1
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param amount0 The delta of the currency0 balance of the pool
    /// @param amount1 The delta of the currency1 balance of the pool
    /// @param activeId The activeId of the pool after the swap
    /// @param fee The fee collected upon every swap in the pool (including protocol fee and LP fee), denominated in hundredths of a bip
    /// @param protocolFee Single direction protocol fee from the swap, also denominated in hundredths of a bip
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint24 activeId,
        uint24 fee,
        uint16 protocolFee
    );

    /// @notice Emitted when liquidity is added
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that modified the pool
    /// @param ids List of binId with liquidity added
    /// @param salt The salt to distinguish different mint from the same owner
    /// @param amounts List of amount added to each bin
    /// @param compositionFeeAmount fee occurred
    /// @param feeAmountToProtocol Protocol fee from the swap: token0 and token1 amount
    event Mint(
        PoolId indexed id,
        address indexed sender,
        uint256[] ids,
        bytes32 salt,
        bytes32[] amounts,
        bytes32 compositionFeeAmount,
        bytes32 feeAmountToProtocol
    );

    /// @notice Emitted when liquidity is removed
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that modified the pool
    /// @param ids List of binId with liquidity removed
    /// @param salt The salt to specify the position to burn if multiple positions are available
    /// @param amounts List of amount removed from each bin
    event Burn(PoolId indexed id, address indexed sender, uint256[] ids, bytes32 salt, bytes32[] amounts);

    /// @notice Emitted when donate happen
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that modified the pool
    /// @param amount0 The delta of the currency0 balance of the pool
    /// @param amount1 The delta of the currency1 balance of the pool
    /// @param binId The donated bin id
    event Donate(PoolId indexed id, address indexed sender, int128 amount0, int128 amount1, uint24 binId);

    /// @notice Emitted when min share for donate is updated
    event SetMinBinSharesForDonate(uint256 minLiquidity);

    /// @notice Emitted when bin step is updated
    event SetMaxBinStep(uint16 maxBinStep);

    struct MintParams {
        bytes32[] liquidityConfigs;
        /// @dev amountIn intended
        bytes32 amountIn;
        /// the salt to distinguish different mint from the same owner
        bytes32 salt;
    }

    struct BurnParams {
        /// @notice id of the bin from which to withdraw
        uint256[] ids;
        /// @notice amount of share to burn for each bin
        uint256[] amountsToBurn;
        /// the salt to specify the position to burn if multiple positions are available
        bytes32 salt;
    }

    /// @notice Get the current value in slot0 of the given pool
    function getSlot0(PoolId id) external view returns (uint24 activeId, uint24 protocolFee, uint24 lpFee);

    /// @notice Returns the reserves of a bin
    /// @param id The id of the bin
    /// @return binReserveX The reserve of token X in the bin
    /// @return binReserveY The reserve of token Y in the bin
    /// @return binLiquidity The total liquidity in the bin
    /// @return totalShares The total shares minted in the bin
    function getBin(PoolId id, uint24 binId)
        external
        view
        returns (uint128 binReserveX, uint128 binReserveY, uint256 binLiquidity, uint256 totalShares);

    /// @notice Returns the positon of owner at a binId
    /// @param id The id of PoolKey
    /// @param owner Address of the owner
    /// @param binId The id of the bin
    /// @param salt The salt to distinguish different positions for the same owner
    function getPosition(PoolId id, address owner, uint24 binId, bytes32 salt)
        external
        view
        returns (BinPosition.Info memory position);

    /// @notice Returns the next non-empty bin
    /// @dev The next non-empty bin is the bin with a higher (if swapForY is true) or lower (if swapForY is false)
    ///     id that has a non-zero reserve of token X or Y.
    /// @param swapForY Whether the swap is for token Y (true) or token X (false)
    /// @param id The id of the bin
    /// @return nextId The id of the next non-empty bin
    function getNextNonEmptyBin(PoolId id, bool swapForY, uint24 binId) external view returns (uint24 nextId);

    /// @notice Initialize a new pool
    function initialize(PoolKey memory key, uint24 activeId) external;

    /// @notice Add liquidity to a pool
    /// @dev For the first liquidity added to a bin, the share minted would be slightly lessser (1e3 lesser) to prevent
    /// share inflation attack.
    /// @return delta BalanceDelta, will be negative indicating how much total amt0 and amt1 liquidity added
    /// @return mintArray Liquidity added in which ids, how much amt0, amt1 and how much liquidity added
    function mint(PoolKey memory key, IBinPoolManager.MintParams calldata params, bytes calldata hookData)
        external
        returns (BalanceDelta delta, BinPool.MintArrays memory mintArray);

    /// @notice Remove liquidity from a pool
    /// @return delta BalanceDelta, will be positive indicating how much total amt0 and amt1 liquidity removed
    function burn(PoolKey memory key, IBinPoolManager.BurnParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta);

    /// @notice Peform a swap to a pool
    /// @param key The pool key
    /// @param swapForY If true, swap token X for Y, if false, swap token Y for X
    /// @param amountSpecified If negative, imply exactInput, if positive, imply exactOutput.
    function swap(PoolKey memory key, bool swapForY, int128 amountSpecified, bytes calldata hookData)
        external
        returns (BalanceDelta delta);

    /// @notice Donate the given currency amounts to the active bin liquidity providers of a pool
    /// @dev Calls to donate can be frontrun adding just-in-time liquidity, with the aim of receiving a portion donated funds.
    /// Donors should keep this in mind when designing donation mechanisms.
    /// @param key The pool to donate to
    /// @param amount0 The amount of currency0 to donate
    /// @param amount1 The amount of currency1 to donate
    /// @param hookData Any data to pass to the callback
    /// @return delta Negative amt means the caller owes the vault, while positive amt means the vault owes the caller
    /// @return binId The donated bin id, which is the current active bin id. if no-op happen, binId will be 0
    function donate(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookData)
        external
        returns (BalanceDelta delta, uint24 binId);

    /// @notice Set max bin step for BinPool
    /// @dev To be realistic, its highly unlikely a pool type with > 100 bin step is required. (>1% price jump per bin)
    function setMaxBinStep(uint16 maxBinStep) external;

    /// @notice Set min shares in bin before donate is allowed in current bin
    /// @dev Bin share is 1:1 liquidity when liquidity is first added. And liquidity: price * x + y << 128, where price is a 128.128 number. A
    ///         min share amount required in the bin for donate prevents share inflation attack.
    /// Min share should always be greater than 0, there should be a validation on BinPoolManagerOwner to prevent setting min share to 0
    function setMinBinSharesForDonate(uint256 minShare) external;
}
