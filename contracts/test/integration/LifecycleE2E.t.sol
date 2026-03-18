// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";
import {SettlementExecutor} from "../../src/SettlementExecutor.sol";

contract LifecycleE2ETest is Test {
    MockERC20 internal collateral;
    VolatilityShareToken internal share;
    VolatilityMarket internal market;
    SettlementExecutor internal executor;

    bytes32 internal constant POOL_ID = keccak256("pool-e2e");

    address internal callbackProxy = address(0xCA11BACC);
    address internal reactVmId = address(0xB0A7);
    address internal longTrader = address(0xAAA1);
    address internal shortTrader = address(0xBBB1);

    function setUp() public {
        collateral = new MockERC20("Collateral", "COL");
        share = new VolatilityShareToken("ipfs://vol/{id}.json", address(this));
        market = new VolatilityMarket(collateral, share, address(this));

        executor = new SettlementExecutor(market, callbackProxy, reactVmId, address(this));

        share.setMarket(address(market));
        market.setSettlementExecutor(address(executor));
        market.createVolatilityPool(POOL_ID, 1 days, 1e18, 1_000e18, 100e18);

        collateral.mint(longTrader, 1_000e18);
        collateral.mint(shortTrader, 1_000e18);

        vm.prank(longTrader);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(shortTrader);
        collateral.approve(address(market), type(uint256).max);
    }

    function testLifecycle_OpenSettleClaim() public {
        vm.prank(longTrader);
        uint256 longPosition = market.openPosition(POOL_ID, true, 100e18);

        vm.prank(shortTrader);
        uint256 shortPosition = market.openPosition(POOL_ID, false, 100e18);

        vm.warp(block.timestamp + 1 days + 1);

        bytes32 replayKey = keccak256("e2e-replay");
        vm.prank(callbackProxy);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 150e18, 100e18, replayKey);

        vm.prank(longTrader);
        market.claim(longPosition);

        vm.prank(shortTrader);
        market.claim(shortPosition);

        assertEq(collateral.balanceOf(longTrader), 1_100e18);
        assertEq(collateral.balanceOf(shortTrader), 900e18);

        (, , , uint256 nextSettlementPrice, , ,) = market.epochs(POOL_ID, 2);
        assertEq(nextSettlementPrice, 150e18);
    }
}
