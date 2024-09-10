// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ILBFactory, ILBPair, LBHelper} from "./helpers/LBHelper.sol";
import {Vault} from "../../src/Vault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {BinPoolManager} from "../../src/pool-bin/BinPoolManager.sol";
import {IBinPoolManager} from "../../src/pool-bin/interfaces/IBinPoolManager.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {BinPoolParametersHelper} from "../../src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinTestHelper} from "./helpers/BinTestHelper.sol";
import {BinLiquidityHelper} from "./helpers/BinLiquidityHelper.sol";
import {BinSwapHelper} from "./helpers/BinSwapHelper.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {BinPosition} from "../../src/pool-bin/libraries/BinPosition.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PackedUint128Math} from "../../src/pool-bin/libraries/math/PackedUint128Math.sol";
import {PriceHelper} from "../../src/pool-bin/libraries/PriceHelper.sol";

abstract contract LBFuzzer is LBHelper, BinTestHelper {
    using BinPoolParametersHelper for bytes32;
    using PackedUint128Math for bytes32;

    IVault vault;
    IBinPoolManager manager;

    BinLiquidityHelper liquidityHelper;
    BinSwapHelper swapHelper;

    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public virtual override {
        super.setUp();

        vault = new Vault();
        manager = new BinPoolManager(vault);
        vault.registerApp(address(manager));
        swapHelper = new BinSwapHelper(manager, vault);
        liquidityHelper = new BinLiquidityHelper(manager, vault);

        token0 = new MockERC20("TestA", "A", 18);
        token1 = new MockERC20("TestB", "B", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));
        token0.mint(address(this), 10 ** 36);
        token1.mint(address(this), 10 ** 36);

        // add to whitelist required by lb
        lbFactory.addQuoteAsset(address(token0));
        lbFactory.addQuoteAsset(address(token1));

        token0.approve(address(swapHelper), type(uint256).max);
        token1.approve(address(swapHelper), type(uint256).max);
        token0.approve(address(liquidityHelper), type(uint256).max);
        token1.approve(address(liquidityHelper), type(uint256).max);
    }

    function _getBoundId(uint16 binStep, uint24 id) internal pure returns (uint24) {
        uint256 maxId = PriceHelper.getIdFromPrice(type(uint128).max, binStep);
        uint256 minId = PriceHelper.getIdFromPrice(1, binStep);
        return uint24(bound(id, minId, maxId));
    }

    function initPools(uint16 binStep, uint24 activeId)
        public
        returns (ILBPair lbPair, PoolKey memory key_, uint16 boundBinStep, uint24 boundActiveId)
    {
        boundBinStep = uint16(bound(binStep, manager.MIN_BIN_STEP(), manager.MAX_BIN_STEP()));
        boundActiveId = _getBoundId(boundBinStep, activeId);

        // lb init
        lbPair = ILBPair(lbFactory.createLBPair(address(token0), address(token1), boundActiveId, boundBinStep));

        // v4#bin init
        key_ = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: IHooks(address(0)),
            poolManager: manager,
            // we've applied the cl-pool styled fee mechanism to bin-pool
            // which is completely different from existing one
            // hence set fee to 0 to avoid interference
            fee: 0,
            parameters: bytes32(0).setBinStep(boundBinStep)
        });
        manager.initialize(key_, boundActiveId, "");
    }

    function mint(ILBPair lbPair, PoolKey memory key, uint24 boundId, uint256 amountX, uint256 amountY, uint8 binNum)
        public
    {
        binNum = uint8(bound(binNum, 1, 20));
        amountX = bound(amountX, 0.1 ether, 10000 ether);
        amountY = bound(amountY, 0.1 ether, 10000 ether);
        // construct bin mint params
        (IBinPoolManager.MintParams memory mintParams,) =
            _getMultipleBinMintParams(boundId, amountX, amountY, binNum, binNum);

        // lb mint
        token0.transfer(address(lbPair), amountX);
        token1.transfer(address(lbPair), amountY);
        (, bytes32 amountsLeft, uint256[] memory liquidityMinted) =
            lbPair.mint(address(this), mintParams.liquidityConfigs, address(this));

        // calc v4 positon share before mint
        uint256[] memory sharesBefore = new uint256[](liquidityMinted.length);
        for (uint256 i = 0; i < liquidityMinted.length; i++) {
            uint24 id = uint24(uint256(mintParams.liquidityConfigs[i]));
            BinPosition.Info memory positionInfo = manager.getPosition(key.toId(), address(liquidityHelper), id, 0);
            sharesBefore[i] = positionInfo.share;
        }

        // v4#bin mint
        BalanceDelta delta = liquidityHelper.mint(key, mintParams, "");

        // check
        assertEq(
            amountX - amountsLeft.decodeX(),
            uint256(int256(-delta.amount0())),
            "Expecting to consume same amount of tokenX !"
        );
        assertEq(
            amountY - amountsLeft.decodeY(),
            uint256(int256(-delta.amount1())),
            "Expecting to consume same amount of tokenY !"
        );
        for (uint256 i = 0; i < liquidityMinted.length; i++) {
            uint24 id = uint24(uint256(mintParams.liquidityConfigs[i]));
            BinPosition.Info memory positionInfoAfter = manager.getPosition(key.toId(), address(liquidityHelper), id, 0);
            assertEq(
                liquidityMinted[i], positionInfoAfter.share - sharesBefore[i], "Expecting to mint same liquidity !"
            );
        }
    }

    function swap(ILBPair lbPair, PoolKey memory key, bool swapForY, uint128 amountIn) public {
        amountIn = uint128(bound(amountIn, 0.1 ether, 10000 ether));
        // v4#bin swap
        BinSwapHelper.TestSettings memory testSettings =
            BinSwapHelper.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        bool shouldRevert = false;
        BalanceDelta balanceDelta;
        try swapHelper.swap(key, swapForY, -int128(amountIn), testSettings, "") returns (BalanceDelta _balanceDelta) {
            balanceDelta = _balanceDelta;
        } catch {
            shouldRevert = true;
        }

        // lb swap
        if (swapForY) {
            token0.transfer(address(lbPair), uint256(amountIn));
        } else {
            token1.transfer(address(lbPair), uint256(amountIn));
        }

        // happens when go out of liquidity
        if (shouldRevert) {
            vm.expectRevert();
        }
        bytes32 amtOut = lbPair.swap(swapForY, address(this));

        if (swapForY) {
            assertEq(
                uint256(int256(balanceDelta.amount1())), uint256(amtOut.decodeY()), "Expecting to swap same amount !"
            );
        } else {
            assertEq(
                uint256(int256(balanceDelta.amount0())), uint256(amtOut.decodeX()), "Expecting to swap same amount !"
            );
        }
    }
}

contract BinPoolManagerBehaviorComparisonTest is LBFuzzer {
    function testMintFuzz(uint16 binStep, uint24 activeId, uint256 amountX, uint256 amountY, uint8 binNum) public {
        (ILBPair lbPair, PoolKey memory key_,, uint24 boundActiveId) = initPools(binStep, activeId);
        mint(lbPair, key_, boundActiveId, amountX, amountY, binNum);
    }

    function testSwapFuzz(
        uint16 binStep,
        uint24 activeId,
        uint256 amountX,
        uint256 amountY,
        uint8 binNum,
        bool swapForY,
        uint128 amountIn
    ) public {
        (ILBPair lbPair, PoolKey memory key_,, uint24 boundActiveId) = initPools(binStep, activeId);
        mint(lbPair, key_, boundActiveId, amountX, amountY, binNum);
        swap(lbPair, key_, swapForY, amountIn);
    }

    struct MintParams {
        uint24 id;
        uint256 amountX;
        uint256 amountY;
        uint8 binNum;
    }

    function testSwapWithMutiplePositionsFuzz(
        uint16 binStep,
        uint24 activeId,
        MintParams[] memory mintParams,
        bool swapForY,
        uint128 amountIn
    ) public {
        (ILBPair lbPair, PoolKey memory key_, uint16 boundBinStep,) = initPools(binStep, activeId);
        for (uint256 i = 0; i < mintParams.length; i++) {
            // at most 10 positions
            if (i == 10) {
                break;
            }
            uint24 boundId = _getBoundId(boundBinStep, mintParams[i].id);
            mint(lbPair, key_, boundId, mintParams[i].amountX, mintParams[i].amountY, mintParams[i].binNum);
        }
        swap(lbPair, key_, swapForY, amountIn);
    }
}
