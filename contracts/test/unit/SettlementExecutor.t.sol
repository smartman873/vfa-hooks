// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";
import {SettlementExecutor} from "../../src/SettlementExecutor.sol";

contract SettlementExecutorTest is Test {
    MockERC20 internal collateral;
    VolatilityShareToken internal share;
    VolatilityMarket internal market;
    SettlementExecutor internal executor;

    address internal callbackProxy = address(0xCA11BACC);
    address internal reactVmId = address(0x1234);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    bytes32 internal constant POOL_ID = keccak256("pool-2");

    function setUp() public {
        collateral = new MockERC20("Collateral", "COL");
        share = new VolatilityShareToken("ipfs://vol/{id}.json", address(this));
        market = new VolatilityMarket(collateral, share, address(this));

        executor = new SettlementExecutor(market, callbackProxy, reactVmId, address(this));

        share.setMarket(address(market));
        market.setSettlementExecutor(address(executor));
        market.createVolatilityPool(POOL_ID, 1 days, 1e18, 1_000e18, 100e18);

        collateral.mint(alice, 100e18);
        collateral.mint(bob, 100e18);

        vm.prank(alice);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateral.approve(address(market), type(uint256).max);

        vm.prank(alice);
        market.openPosition(POOL_ID, true, 50e18);
        vm.prank(bob);
        market.openPosition(POOL_ID, false, 50e18);

        vm.warp(block.timestamp + 1 days + 1);
    }

    function testRejectsUnauthorizedCallbackSender() public {
        vm.expectRevert(SettlementExecutor.UnauthorizedCallbackProxy.selector);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 120e18, 100e18, keccak256("rk-x"));
    }

    function testRejectsInvalidReactVmId() public {
        vm.prank(callbackProxy);
        vm.expectRevert(SettlementExecutor.InvalidReactVmId.selector);
        executor.settleEpoch(address(0x999), POOL_ID, 1, 120e18, 100e18, keccak256("rk-y"));
    }

    function testReplayProtectionAndIdempotency() public {
        bytes32 replayKey = keccak256("rk-z");

        vm.prank(callbackProxy);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 120e18, 100e18, replayKey);

        vm.prank(callbackProxy);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 120e18, 100e18, replayKey);

        assertTrue(executor.processedReplayKeys(replayKey));
        assertTrue(market.isEpochSettled(POOL_ID, 1));
    }
}
