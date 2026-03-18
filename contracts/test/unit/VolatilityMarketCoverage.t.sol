// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";
import {EncodingLibrary} from "../../src/libraries/EncodingLibrary.sol";

contract VolatilityMarketCoverageTest is Test {
    using stdStorage for StdStorage;

    MockERC20 internal collateral;
    VolatilityShareToken internal share;
    VolatilityMarket internal market;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal executor = address(this);

    bytes32 internal constant POOL_ID = keccak256("coverage-pool");

    function setUp() public {
        collateral = new MockERC20("Collateral", "COL");
        share = new VolatilityShareToken("ipfs://vol/{id}.json", address(this));
        market = new VolatilityMarket(collateral, share, address(this));

        share.setMarket(address(market));
        market.setSettlementExecutor(executor);
        market.createVolatilityPool(POOL_ID, 1 days, 1e18, 1_000e18, 100e18);

        collateral.mint(alice, 1_000e18);
        collateral.mint(bob, 1_000e18);

        vm.prank(alice);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateral.approve(address(market), type(uint256).max);
    }

    function testSetSettlementExecutorRejectsZero() public {
        vm.expectRevert("zero executor");
        market.setSettlementExecutor(address(0));
    }

    function testCreatePoolValidation() public {
        vm.expectRevert("pool exists");
        market.createVolatilityPool(POOL_ID, 1 days, 1e18, 1_000e18, 100e18);

        bytes32 poolB = keccak256("pool-b");
        vm.expectRevert("epochDuration=0");
        market.createVolatilityPool(poolB, 0, 1e18, 1_000e18, 100e18);

        poolB = keccak256("pool-c");
        vm.expectRevert("invalid trade bounds");
        market.createVolatilityPool(poolB, 1 days, 2e18, 1e18, 100e18);

        poolB = keccak256("pool-d");
        vm.expectRevert("baseline=0");
        market.createVolatilityPool(poolB, 1 days, 1e18, 1_000e18, 0);
    }

    function testOpenPositionRevertsForUnknownPoolAndBoundsAndInactiveEpoch() public {
        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.UnknownPool.selector);
        market.openPosition(keccak256("unknown"), true, 10e18);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.TradeSizeOutOfBounds.selector);
        market.openPosition(POOL_ID, true, 1e17);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.EpochNotActive.selector);
        market.openPosition(POOL_ID, true, 10e18);
    }

    function testClosePositionCoversShortPathAndInactivityReverts() public {
        vm.prank(bob);
        uint256 shortPos = market.openPosition(POOL_ID, false, 20e18);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.InvalidPositionOwner.selector);
        market.closePosition(shortPos);

        vm.prank(bob);
        market.closePosition(shortPos);

        (, , , , , uint256 totalShort,) = market.epochs(POOL_ID, 1);
        assertEq(totalShort, 0);

        vm.prank(alice);
        uint256 longPos = market.openPosition(POOL_ID, true, 10e18);
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.EpochNotActive.selector);
        market.closePosition(longPos);
    }

    function testClosePositionUnknownPoolBranchViaTamperedPosition() public {
        vm.prank(alice);
        uint256 positionId = market.openPosition(POOL_ID, true, 10e18);

        uint256 poolIdSlot = stdstore.target(address(market)).sig("positions(uint256)").with_key(positionId).depth(1).find();
        vm.store(address(market), bytes32(poolIdSlot), keccak256("non-existent-pool"));

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.UnknownPool.selector);
        market.closePosition(positionId);
    }

    function testClosePositionRevertsWhenClaimedFlagIsSet() public {
        vm.prank(alice);
        uint256 positionId = market.openPosition(POOL_ID, true, 10e18);

        vm.warp(block.timestamp + 1 days + 1);
        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("claimed-flag"));

        vm.prank(alice);
        market.claim(positionId);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.PositionClosedError.selector);
        market.closePosition(positionId);
    }

    function testFinalizeEpochValidationAndExecutorGuard() public {
        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.NotSettlementExecutor.selector);
        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("unauthorized"));

        vm.expectRevert(VolatilityMarket.UnknownPool.selector);
        market.finalizeEpoch(keccak256("missing"), 1, 120e18, 100e18, keccak256("unknown"));

        vm.expectRevert(VolatilityMarket.InvalidEpoch.selector);
        market.finalizeEpoch(POOL_ID, 2, 120e18, 100e18, keccak256("future"));

        vm.expectRevert(VolatilityMarket.EpochNotEnded.selector);
        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("not-ended"));
    }

    function testFinalizeEpochRejectsOutOfBoundsVolAndSettlementMismatch() public {
        vm.warp(block.timestamp + 1 days + 1);
        uint256 maxRealized = market.MAX_REALIZED_VOLATILITY();

        vm.expectRevert(VolatilityMarket.RealizedVolatilityOutOfBounds.selector);
        market.finalizeEpoch(POOL_ID, 1, maxRealized + 1, 100e18, keccak256("vol"));

        vm.expectRevert(VolatilityMarket.SettlementPriceMismatch.selector);
        market.finalizeEpoch(POOL_ID, 1, 120e18, 99e18, keccak256("price"));
    }

    function testFinalizeEpochCoversAllPayoutBranches() public {
        vm.warp(block.timestamp + 1 days + 1);

        market.finalizeEpoch(POOL_ID, 1, 100e18, 100e18, keccak256("both-zero"));
        assertEq(market.longPayoutPerShare(POOL_ID, 1), market.ONE());
        assertEq(market.shortPayoutPerShare(POOL_ID, 1), market.ONE());
    }

    function testFinalizeEpochTotalLongZeroBranch() public {
        vm.prank(bob);
        market.openPosition(POOL_ID, false, 50e18);
        vm.warp(block.timestamp + 1 days + 1);

        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("no-longs"));

        assertEq(market.longPayoutPerShare(POOL_ID, 1), 0);
        assertEq(market.shortPayoutPerShare(POOL_ID, 1), market.ONE());
    }

    function testFinalizeEpochTotalShortZeroBranch() public {
        vm.prank(alice);
        market.openPosition(POOL_ID, true, 50e18);
        vm.warp(block.timestamp + 1 days + 1);

        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("no-shorts"));

        assertEq(market.longPayoutPerShare(POOL_ID, 1), market.ONE());
        assertEq(market.shortPayoutPerShare(POOL_ID, 1), 0);
    }

    function testFinalizeEpochShortWinsAndEqualBranches() public {
        vm.prank(alice);
        uint256 longPos = market.openPosition(POOL_ID, true, 100e18);
        vm.prank(bob);
        uint256 shortPos = market.openPosition(POOL_ID, false, 100e18);
        vm.warp(block.timestamp + 1 days + 1);

        market.finalizeEpoch(POOL_ID, 1, 50e18, 100e18, keccak256("short-wins"));

        assertEq(market.longPayoutPerShare(POOL_ID, 1), 0);
        assertGt(market.shortPayoutPerShare(POOL_ID, 1), market.ONE());

        vm.prank(alice);
        market.claim(longPos);
        assertEq(collateral.balanceOf(alice), 900e18);

        vm.prank(bob);
        market.claim(shortPos);
        assertEq(collateral.balanceOf(bob), 1_100e18);

        vm.prank(alice);
        uint256 longPos2 = market.openPosition(POOL_ID, true, 20e18);
        vm.prank(bob);
        uint256 shortPos2 = market.openPosition(POOL_ID, false, 20e18);
        vm.warp(block.timestamp + 1 days + 1);

        market.finalizeEpoch(POOL_ID, 2, 50e18, 50e18, keccak256("equal"));
        assertEq(market.longPayoutPerShare(POOL_ID, 2), market.ONE());
        assertEq(market.shortPayoutPerShare(POOL_ID, 2), market.ONE());

        vm.prank(alice);
        market.claim(longPos2);
        vm.prank(bob);
        market.claim(shortPos2);
    }

    function testFinalizeEpochCurrentMismatchInvalidEpochBranch() public {
        vm.warp(block.timestamp + 1 days + 1);
        market.finalizeEpoch(POOL_ID, 1, 100e18, 100e18, keccak256("epoch-1"));

        vm.expectRevert(VolatilityMarket.InvalidEpoch.selector);
        market.finalizeEpoch(POOL_ID, 0, 100e18, 0, keccak256("epoch-0"));
    }

    function testClaimGuards() public {
        vm.prank(alice);
        uint256 pos = market.openPosition(POOL_ID, true, 10e18);

        vm.prank(bob);
        vm.expectRevert(VolatilityMarket.InvalidPositionOwner.selector);
        market.claim(pos);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.EpochNotSettled.selector);
        market.claim(pos);

        vm.prank(alice);
        market.closePosition(pos);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.PositionClosedError.selector);
        market.claim(pos);
    }

    function testClaimSettledPositionCannotBeClaimedTwice() public {
        vm.prank(alice);
        uint256 longPos = market.openPosition(POOL_ID, true, 100e18);
        vm.prank(bob);
        market.openPosition(POOL_ID, false, 100e18);

        vm.warp(block.timestamp + 1 days + 1);
        market.finalizeEpoch(POOL_ID, 1, 150e18, 100e18, keccak256("double-claim"));

        vm.prank(alice);
        market.claim(longPos);

        vm.prank(alice);
        vm.expectRevert(VolatilityMarket.PositionClosedError.selector);
        market.claim(longPos);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzOpenPositionTracksTotals(bool isLong, uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1e18, 1_000e18);
        address trader = isLong ? alice : bob;

        vm.prank(trader);
        uint256 positionId = market.openPosition(POOL_ID, isLong, amount);

        if (isLong) {
            (, , , , uint256 totalLong,,) = market.epochs(POOL_ID, 1);
            assertEq(totalLong, amount);
        } else {
            (, , , , , uint256 totalShort,) = market.epochs(POOL_ID, 1);
            assertEq(totalShort, amount);
        }

        (address owner, bytes32 poolId, uint256 epochId, uint256 positionAmount, bool longSide,,) = market.positions(positionId);
        assertEq(owner, trader);
        assertEq(poolId, POOL_ID);
        assertEq(epochId, 1);
        assertEq(positionAmount, amount);
        assertEq(longSide, isLong);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzSettlementConservesCollateral(uint96 longRaw, uint96 shortRaw, bool longWins) public {
        uint256 longAmount = bound(uint256(longRaw), 1e18, 200e18);
        uint256 shortAmount = bound(uint256(shortRaw), 1e18, 200e18);

        vm.prank(alice);
        uint256 longPos = market.openPosition(POOL_ID, true, longAmount);
        vm.prank(bob);
        uint256 shortPos = market.openPosition(POOL_ID, false, shortAmount);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 realizedVol = longWins ? 120e18 : 80e18;
        market.finalizeEpoch(POOL_ID, 1, realizedVol, 100e18, keccak256(abi.encode(longAmount, shortAmount, longWins)));

        vm.prank(alice);
        market.claim(longPos);
        vm.prank(bob);
        market.claim(shortPos);

        uint256 total = collateral.balanceOf(alice) + collateral.balanceOf(bob) + collateral.balanceOf(address(market));
        assertEq(total, 2_000e18);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzShareTokenIdsAreConsistent(bool isLong, uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1e18, 10e18);

        vm.prank(alice);
        uint256 positionId = market.openPosition(POOL_ID, isLong, amount);

        uint256 expectedTokenId = EncodingLibrary.shareTokenId(POOL_ID, 1, isLong);
        assertEq(share.balanceOf(alice, expectedTokenId), amount);

        vm.prank(alice);
        market.closePosition(positionId);
        assertEq(share.balanceOf(alice, expectedTokenId), 0);
    }
}
