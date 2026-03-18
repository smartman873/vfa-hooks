// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";

contract VolatilityMarketTest is Test {
    MockERC20 internal collateral;
    VolatilityShareToken internal share;
    VolatilityMarket internal market;

    address internal executor = address(0xBEEF);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    bytes32 internal constant POOL_ID = keccak256("pool-1");

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

    function testOpenAndClosePositionBeforeSettlement() public {
        vm.prank(alice);
        uint256 positionId = market.openPosition(POOL_ID, true, 100e18);

        vm.prank(alice);
        market.closePosition(positionId);

        (, , , , uint256 totalLong,,) = market.epochs(POOL_ID, 1);
        assertEq(totalLong, 0);
        assertEq(collateral.balanceOf(alice), 1_000e18);
    }

    function testFinalizeAndClaimLongWins() public {
        vm.prank(alice);
        uint256 longPos = market.openPosition(POOL_ID, true, 100e18);

        vm.prank(bob);
        uint256 shortPos = market.openPosition(POOL_ID, false, 100e18);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(executor);
        market.finalizeEpoch(POOL_ID, 1, 150e18, 100e18, keccak256("rk-1"));

        vm.prank(alice);
        market.claim(longPos);

        vm.prank(bob);
        market.claim(shortPos);

        assertEq(collateral.balanceOf(alice), 1_100e18);
        assertEq(collateral.balanceOf(bob), 900e18);

        (, , , , , , bool settled) = market.epochs(POOL_ID, 1);
        assertTrue(settled);
    }

    function testFinalizeIdempotentWithSameEpoch() public {
        vm.prank(alice);
        market.openPosition(POOL_ID, true, 10e18);
        vm.prank(bob);
        market.openPosition(POOL_ID, false, 10e18);

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(executor);
        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("rk-2"));
        market.finalizeEpoch(POOL_ID, 1, 120e18, 100e18, keccak256("rk-2-dup"));
        vm.stopPrank();

        (, , , , , , bool settled) = market.epochs(POOL_ID, 1);
        assertTrue(settled);
    }
}
