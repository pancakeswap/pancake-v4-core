// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.24;

import {BalanceDelta, toBalanceDelta} from "../../types/BalanceDelta.sol";
import {LiquidityConfigurations} from "./math/LiquidityConfigurations.sol";
import {PackedUint128Math} from "./math/PackedUint128Math.sol";
import {Uint256x256Math} from "./math/Uint256x256Math.sol";
import {TreeMath} from "./math/TreeMath.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {BinHelper} from "./BinHelper.sol";
import {BinPosition} from "./BinPosition.sol";
import {SafeCast} from "./math/SafeCast.sol";
import {Constants} from "./Constants.sol";
import {FeeHelper} from "./FeeHelper.sol";
import {ProtocolFeeLibrary} from "../../libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "../../libraries/LPFeeLibrary.sol";

library BinPool {
    using BinHelper for bytes32;
    using LiquidityConfigurations for bytes32;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using PriceHelper for uint24;
    using Uint256x256Math for uint256;
    using BinPosition for mapping(bytes32 => BinPosition.Info);
    using BinPosition for BinPosition.Info;
    using TreeMath for bytes32;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using FeeHelper for uint128;
    using BinPool for State;
    using ProtocolFeeLibrary for uint24;
    using LPFeeLibrary for uint24;

    error PoolNotInitialized();
    error PoolAlreadyInitialized();
    error BinPool__EmptyLiquidityConfigs();
    error BinPool__ZeroShares(uint24 id);
    error BinPool__InvalidBurnInput();
    error BinPool__BurnZeroAmount(uint24 id);
    error BinPool__ZeroAmountsOut(uint24 id);
    error BinPool__OutOfLiquidity();
    error BinPool__NoLiquidityToReceiveFees();
    /// @dev if swap exactIn, x for y, unspecifiedToken = token y. if swap x for exact out y, unspecified token is x
    error BinPool__InsufficientAmountUnSpecified();

    struct Slot0 {
        // the current activeId
        uint24 activeId;
        // protocol fee, expressed in hundredths of a bip
        // upper 12 bits are for 1->0, and the lower 12 are for 0->1
        // the maximum is 1000 - meaning the maximum protocol fee is 0.1%
        // the protocolFee is taken from the input first, then the lpFee is taken from the remaining input
        uint24 protocolFee;
        // lp fee, either static at initialize or dynamic via hook
        uint24 lpFee;
    }

    /// @dev The state of a pool
    struct State {
        Slot0 slot0;
        /// @notice binId ==> (reserve of token x and y in the bin)
        mapping(uint256 binId => bytes32 reserve) reserveOfBin;
        /// @notice binId ==> (total share minted)
        mapping(uint256 binId => uint256 share) shareOfBin;
        /// @notice (user, binId) => shares of user in a binId
        mapping(bytes32 => BinPosition.Info) positions;
        /// @dev todo: cannot nest a struct with mapping, error: recursive type is not allowed for public state variables.
        /// TreeMath.TreeUint24 _tree;
        /// the 3 attributes below come from TreeMath
        bytes32 level0;
        mapping(bytes32 => bytes32) level1;
        mapping(bytes32 => bytes32) level2;
    }

    function initialize(State storage self, uint24 activeId, uint24 protocolFee, uint24 lpFee) internal {
        /// An initialized pool will not have activeId: 0
        if (self.slot0.activeId != 0) revert PoolAlreadyInitialized();

        self.slot0 = Slot0({activeId: activeId, protocolFee: protocolFee, lpFee: lpFee});
    }

    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        self.checkPoolInitialized();
        self.slot0.protocolFee = protocolFee;
    }

    /// @notice Only dynamic fee pools may update the swap fee.
    function setLPFee(State storage self, uint24 lpFee) internal {
        self.checkPoolInitialized();

        self.slot0.lpFee = lpFee;
    }

    struct SwapParams {
        bool swapForY;
        uint16 binStep;
        uint24 lpFeeOverride;
        int128 amountSpecified; // negative for exactInput, positive for exactOutput
    }

    struct SwapState {
        // current activeId
        uint24 activeId;
        // the protocol fee for the swap
        uint24 protocolFee;
        // the swapFee (the total percentage charged within a swap, including the protocol fee and the LP fee)
        uint24 swapFee;
        // how much protocol fee has been charged
        bytes32 feeForProtocol;
    }

    function swap(State storage self, SwapParams memory params)
        internal
        returns (BalanceDelta result, SwapState memory swapState)
    {
        Slot0 memory slot0Cache = self.slot0;
        swapState.activeId = slot0Cache.activeId;
        bool swapForY = params.swapForY;
        swapState.protocolFee =
            swapForY ? slot0Cache.protocolFee.getZeroForOneFee() : slot0Cache.protocolFee.getOneForZeroFee();
        bool exactInput = params.amountSpecified < 0;

        {
            uint24 lpFee = params.lpFeeOverride.isOverride()
                ? params.lpFeeOverride.removeOverrideAndValidate(LPFeeLibrary.TEN_PERCENT_FEE)
                : slot0Cache.lpFee;

            /// @dev swap fee includes protocolFee (charged first) and lpFee
            swapState.swapFee = swapState.protocolFee == 0 ? lpFee : swapState.protocolFee.calculateSwapFee(lpFee);
        }

        /// @notice early return if hook has updated amountSpecified to 0
        if (params.amountSpecified == 0) return (result, swapState);

        uint128 amount;
        unchecked {
            amount = params.amountSpecified > 0 ? uint128(params.amountSpecified) : uint128(-params.amountSpecified);
        }

        /// @dev Amount of token left. In exactIn, refer to how much input left. In exactOut, refer to how much output left
        bytes32 amountsLeft = (swapForY == exactInput) ? amount.encodeFirst() : amount.encodeSecond();

        /// @dev Amount of token on the other side. In exactIn, refer to how much token out. In exactOut, refer to how much token in
        bytes32 amountsUnspecified;

        while (true) {
            bytes32 binReserves = self.reserveOfBin[swapState.activeId];
            if (!binReserves.isEmpty(!swapForY)) {
                bytes32 amountsInWithFees;
                bytes32 amountsOutOfBin;
                bytes32 totalFee;

                if (exactInput) {
                    (amountsInWithFees, amountsOutOfBin, totalFee) = binReserves.getAmountsOut(
                        swapState.swapFee, params.binStep, swapForY, swapState.activeId, amountsLeft
                    );

                    amountsLeft = amountsLeft.sub(amountsInWithFees);
                    amountsUnspecified = amountsUnspecified.add(amountsOutOfBin);
                } else {
                    (amountsInWithFees, amountsOutOfBin, totalFee) = binReserves.getAmountsIn(
                        swapState.swapFee, params.binStep, swapForY, swapState.activeId, amountsLeft
                    );

                    amountsLeft = amountsLeft.sub(amountsOutOfBin);
                    amountsUnspecified = amountsUnspecified.add(amountsInWithFees);
                }

                if (amountsInWithFees > 0) {
                    /// @dev calc protocol fee for current bin, totalFee * protocolFee / (protocolFee + lpFee)
                    bytes32 pFee = totalFee.getExternalFeeAmt(slot0Cache.protocolFee, swapState.swapFee);
                    if (pFee != 0) {
                        swapState.feeForProtocol = swapState.feeForProtocol.add(pFee);
                        amountsInWithFees = amountsInWithFees.sub(pFee);
                    }

                    self.reserveOfBin[swapState.activeId] = binReserves.add(amountsInWithFees).sub(amountsOutOfBin);
                }
            }

            if (amountsLeft == 0) {
                break;
            } else {
                uint24 nextId = getNextNonEmptyBin(self, swapForY, swapState.activeId);
                // Equivalent to: if (nextId == 0 || nextId == type(uint24).max) revert BinPool__OutOfLiquidity();
                assembly ("memory-safe") {
                    if or(iszero(nextId), eq(nextId, 0xffffff)) {
                        mstore(0x00, 0x96aa65ad) // Selector BinPool__OutOfLiquidity()
                        revert(0x1c, 0x04)
                    }
                }
                swapState.activeId = nextId;
            }
        }

        if (amountsUnspecified == 0) revert BinPool__InsufficientAmountUnSpecified();

        self.slot0.activeId = swapState.activeId;
        unchecked {
            // uncheckeck as negating positive int128 is safe
            if (exactInput) {
                if (swapForY) {
                    result = toBalanceDelta(-amount.safeInt128(), amountsUnspecified.decodeY().safeInt128());
                } else {
                    result = toBalanceDelta(amountsUnspecified.decodeX().safeInt128(), -(amount.safeInt128()));
                }
            } else {
                if (swapForY) {
                    result = toBalanceDelta(-amountsUnspecified.decodeX().safeInt128(), amount.safeInt128());
                } else {
                    result = toBalanceDelta(amount.safeInt128(), -(amountsUnspecified.decodeY().safeInt128()));
                }
            }
        }
    }

    struct MintParams {
        address to; // nft minted to
        bytes32[] liquidityConfigs;
        bytes32 amountIn;
        uint16 binStep;
        bytes32 salt;
    }

    struct MintArrays {
        uint256[] ids;
        bytes32[] amounts;
        uint256[] liquidityMinted;
    }

    /// @return result the delta of the token balance of the pool (inclusive of fees)
    /// @return feeForProtocol total protocol fee amount
    /// @return arrays the ids, amounts and liquidity minted for each bin
    /// @return compositionFee composition fee for adding different ratio to active bin
    function mint(State storage self, MintParams memory params)
        internal
        returns (BalanceDelta result, bytes32 feeForProtocol, MintArrays memory arrays, bytes32 compositionFee)
    {
        if (params.liquidityConfigs.length == 0) revert BinPool__EmptyLiquidityConfigs();

        arrays = MintArrays({
            ids: new uint256[](params.liquidityConfigs.length),
            amounts: new bytes32[](params.liquidityConfigs.length),
            liquidityMinted: new uint256[](params.liquidityConfigs.length)
        });

        (bytes32 amountsLeft, bytes32 fee, bytes32 compoFee) = _mintBins(self, params, arrays);
        feeForProtocol = fee;
        compositionFee = compoFee;

        (uint128 x1, uint128 x2) = params.amountIn.sub(amountsLeft).decode();

        // set balanceDelta to negative (so user must settle()) from the vault
        result = toBalanceDelta(-(x1.safeInt128()), -(x2.safeInt128()));
    }

    /// @notice Returns the reserves of a bin
    /// @param binStep The binStep of the bin
    /// @param id The id of the bin
    /// @return binReserveX The reserve of token X in the bin
    /// @return binReserveY The reserve of token Y in the bin
    /// @return binLiquidity The liquidity in the bin
    function getBin(State storage self, uint16 binStep, uint24 id)
        internal
        view
        returns (uint128 binReserveX, uint128 binReserveY, uint256 binLiquidity)
    {
        bytes32 binReserves = self.reserveOfBin[id];

        (binReserveX, binReserveY) = binReserves.decode();
        binLiquidity = binReserves.getLiquidity(id.getPriceFromId(binStep));
    }

    /// @dev Returns next non-empty bin
    /// @param swapForY Whether the swap is for Y
    /// @param id The id of the bin
    /// @return The id of the next non-empty bin
    function getNextNonEmptyBin(State storage self, bool swapForY, uint24 id) internal view returns (uint24) {
        return swapForY
            ? TreeMath.findFirstRight(self.level0, self.level1, self.level2, id)
            : TreeMath.findFirstLeft(self.level0, self.level1, self.level2, id);
    }

    struct BurnParams {
        address from;
        uint256[] ids;
        uint256[] amountsToBurn;
        bytes32 salt;
    }

    /// @notice Burn user's share and withdraw tokens form the pool.
    /// @return result the delta of the token balance of the pool
    function burn(State storage self, BurnParams memory params)
        internal
        returns (BalanceDelta result, uint256[] memory ids, bytes32[] memory amounts)
    {
        ids = params.ids;
        uint256[] memory amountsToBurn = params.amountsToBurn;

        if (ids.length == 0 || ids.length != amountsToBurn.length) revert BinPool__InvalidBurnInput();

        bytes32 amountsOut;
        amounts = new bytes32[](ids.length);
        for (uint256 i; i < ids.length;) {
            uint24 id = ids[i].safe24();
            uint256 amountToBurn = amountsToBurn[i];

            if (amountToBurn == 0) revert BinPool__BurnZeroAmount(id);

            bytes32 binReserves = self.reserveOfBin[id];
            uint256 supply = self.shareOfBin[id];

            _subShare(self, params.from, id, params.salt, amountToBurn);

            bytes32 amountsOutFromBin = binReserves.getAmountOutOfBin(amountToBurn, supply);

            if (amountsOutFromBin == 0) revert BinPool__ZeroAmountsOut(id);

            binReserves = binReserves.sub(amountsOutFromBin);

            if (supply == amountToBurn) _removeBinIdToTree(self, id);

            self.reserveOfBin[id] = binReserves;
            amounts[i] = amountsOutFromBin;
            amountsOut = amountsOut.add(amountsOutFromBin);

            unchecked {
                ++i;
            }
        }

        result = toBalanceDelta(amountsOut.decodeX().safeInt128(), amountsOut.decodeY().safeInt128());
    }

    function donate(State storage self, uint16 binStep, uint128 amount0, uint128 amount1)
        internal
        returns (BalanceDelta result, uint24 activeId)
    {
        activeId = self.slot0.activeId;
        bytes32 amountIn = amount0.encode(amount1);

        bytes32 binReserves = self.reserveOfBin[activeId];
        if (binReserves == 0) revert BinPool__NoLiquidityToReceiveFees();

        /// @dev overflow check on total reserves and the resulting liquidity
        uint256 price = activeId.getPriceFromId(binStep);
        binReserves.add(amountIn).getLiquidity(price);

        self.reserveOfBin[activeId] = binReserves.add(amountIn);
        result = toBalanceDelta(-(amount0.safeInt128()), -(amount1.safeInt128()));
    }

    /// @dev Helper function to mint liquidity in each bin in the liquidity configurations
    /// @param params MintParams (to, liquidityConfig, amountIn, binStep and fee)
    /// @param arrays MintArrays (ids[] , amounts[], liquidityMinted[])
    /// @return amountsLeft amountLeft after deducting all the input (inclusive of fee) from amountIn
    /// @return feeForProtocol total feeForProtocol for minting
    /// @return compositionFee composition fee for adding different ratio to active bin
    function _mintBins(State storage self, MintParams memory params, MintArrays memory arrays)
        private
        returns (bytes32 amountsLeft, bytes32 feeForProtocol, bytes32 compositionFee)
    {
        amountsLeft = params.amountIn;

        uint24 id;
        uint256 shares;
        bytes32 amountsIn;
        bytes32 amountsInToBin;
        bytes32 binFeeAmt;
        bytes32 binCompositionFee;
        for (uint256 i; i < params.liquidityConfigs.length;) {
            // fix stack too deep
            {
                bytes32 maxAmountsInToBin;
                (maxAmountsInToBin, id) = params.liquidityConfigs[i].getAmountsAndId(params.amountIn);

                (shares, amountsIn, amountsInToBin, binFeeAmt, binCompositionFee) =
                    _updateBin(self, params, id, maxAmountsInToBin);
            }

            amountsLeft = amountsLeft.sub(amountsIn);
            feeForProtocol = feeForProtocol.add(binFeeAmt);

            arrays.ids[i] = id;
            arrays.amounts[i] = amountsInToBin;
            arrays.liquidityMinted[i] = shares;

            _addShare(self, params.to, id, params.salt, shares);

            compositionFee = compositionFee.add(binCompositionFee);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Helper function to update a bin during minting
    /// @param id The id of the bin
    /// @param maxAmountsInToBin The maximum amounts in to the bin
    /// @return shares The amount of shares minted
    /// @return amountsIn The amounts in
    /// @return amountsInToBin The amounts in to the bin
    /// @return feeForProtocol The amounts of fee for protocol
    /// @return compositionFee The total amount of composition fee
    function _updateBin(State storage self, MintParams memory params, uint24 id, bytes32 maxAmountsInToBin)
        internal
        returns (
            uint256 shares,
            bytes32 amountsIn,
            bytes32 amountsInToBin,
            bytes32 feeForProtocol,
            bytes32 compositionFee
        )
    {
        Slot0 memory slot0Cache = self.slot0;
        uint24 activeId = slot0Cache.activeId;
        bytes32 binReserves = self.reserveOfBin[id];

        uint256 price = id.getPriceFromId(params.binStep);
        uint256 supply = self.shareOfBin[id];

        (shares, amountsIn) = binReserves.getSharesAndEffectiveAmountsIn(maxAmountsInToBin, price, supply);
        amountsInToBin = amountsIn;

        if (id == activeId) {
            // Fees happens when user try to add liquidity in active bin but with different ratio of (x, y)
            /// eg. current bin is 40/60 (a,b) but user tries to add liquidity with 50/50 ratio
            bytes32 fees;
            (fees, feeForProtocol) =
                binReserves.getCompositionFees(slot0Cache.protocolFee, slot0Cache.lpFee, amountsIn, supply, shares);
            compositionFee = fees;
            if (fees != 0) {
                {
                    uint256 userLiquidity = amountsIn.sub(fees).getLiquidity(price);
                    uint256 binLiquidity = binReserves.getLiquidity(price);
                    shares = userLiquidity.mulDivRoundDown(supply, binLiquidity);
                }

                if (feeForProtocol != 0) {
                    amountsInToBin = amountsInToBin.sub(feeForProtocol);
                }
            }
        } else {
            amountsIn.verifyAmounts(activeId, id);
        }

        if (shares == 0 || amountsInToBin == 0) revert BinPool__ZeroShares(id);
        if (supply == 0) _addBinIdToTree(self, id);

        self.reserveOfBin[id] = binReserves.add(amountsInToBin);
    }

    /// @notice Subtract share from user's position and update total share supply of bin
    function _subShare(State storage self, address owner, uint24 binId, bytes32 salt, uint256 shares) internal {
        self.positions.get(owner, binId, salt).subShare(shares);
        self.shareOfBin[binId] -= shares;
    }

    /// @notice Add share to user's position and update total share supply of bin
    function _addShare(State storage self, address owner, uint24 binId, bytes32 salt, uint256 shares) internal {
        self.positions.get(owner, binId, salt).addShare(shares);
        self.shareOfBin[binId] += shares;
    }

    /// @notice Enable bin id for a pool
    function _addBinIdToTree(State storage self, uint24 binId) internal {
        (, self.level0) = TreeMath.add(self.level0, self.level1, self.level2, binId);
    }

    /// @notice remove bin id for a pool
    function _removeBinIdToTree(State storage self, uint24 binId) internal {
        (, self.level0) = TreeMath.remove(self.level0, self.level1, self.level2, binId);
    }

    function checkPoolInitialized(State storage self) internal view {
        if (self.slot0.activeId == 0) {
            // revert PoolNotInitialized();
            assembly ("memory-safe") {
                mstore(0x00, 0x486aa307)
                revert(0x1c, 0x04)
            }
        }
    }
}
