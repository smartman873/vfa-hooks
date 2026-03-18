// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";
import {VolatilityMarket} from "../../src/VolatilityMarket.sol";
import {SettlementExecutor} from "../../src/SettlementExecutor.sol";
import {IVolatilityMarket} from "../../src/interfaces/IVolatilityMarket.sol";

contract SettlementExecutorCoverageTest is Test {
    MockERC20 internal collateral;
    VolatilityShareToken internal share;
    VolatilityMarket internal market;
    SettlementExecutor internal executor;

    address internal callbackProxy = address(0xCA11BACC);
    address internal reactVmId = address(0x1234);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    bytes32 internal constant POOL_ID = keccak256("executor-coverage-pool");

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
    }

    function testConstructorRejectsInvalidInputs() public {
        vm.expectRevert("zero market");
        new SettlementExecutor(IVolatilityMarket(address(0)), callbackProxy, reactVmId, address(this));

        vm.expectRevert("zero callbackProxy");
        new SettlementExecutor(market, address(0), reactVmId, address(this));

        vm.expectRevert("zero reactVmId");
        new SettlementExecutor(market, callbackProxy, address(0), address(this));
    }

    function testSetterAccessControlAndValidation() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        executor.setCallbackProxy(address(0xBEEF));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        executor.setExpectedReactVmId(address(0xBEEF));

        vm.expectRevert("zero callbackProxy");
        executor.setCallbackProxy(address(0));

        vm.expectRevert("zero reactVmId");
        executor.setExpectedReactVmId(address(0));

        executor.setCallbackProxy(address(0xBEEF));
        assertEq(executor.callbackProxy(), address(0xBEEF));

        executor.setExpectedReactVmId(address(0xFACE));
        assertEq(executor.expectedReactVmId(), address(0xFACE));
    }

    function testManualSettlementPathAndReplayReturn() public {
        _seedEpochWithPositions();

        bytes32 replayKey = keccak256("manual-replay");
        executor.settleEpochManual(POOL_ID, 1, 120e18, 100e18, replayKey);
        assertTrue(executor.processedReplayKeys(replayKey));
        assertTrue(market.isEpochSettled(POOL_ID, 1));

        executor.settleEpochManual(POOL_ID, 1, 120e18, 100e18, replayKey);
        assertTrue(executor.processedReplayKeys(replayKey));
    }

    function testManualSettlementOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        executor.settleEpochManual(POOL_ID, 1, 120e18, 100e18, keccak256("non-owner"));
    }

    function testPayRequiresAuthorizedSender() public {
        vm.deal(address(executor), 1 ether);

        vm.prank(alice);
        vm.expectRevert("Authorized sender only");
        executor.pay(0.1 ether);
    }

    function testPayFromCallbackProxyAndRotateAuthorization() public {
        vm.deal(address(executor), 2 ether);

        uint256 oldProxyBefore = callbackProxy.balance;
        vm.prank(callbackProxy);
        executor.pay(0.25 ether);
        assertEq(callbackProxy.balance, oldProxyBefore + 0.25 ether);

        address newCallbackProxy = address(0xBEEF);
        executor.setCallbackProxy(newCallbackProxy);

        vm.prank(callbackProxy);
        vm.expectRevert("Authorized sender only");
        executor.pay(0.1 ether);

        uint256 newProxyBefore = newCallbackProxy.balance;
        vm.prank(newCallbackProxy);
        executor.pay(0.2 ether);
        assertEq(newCallbackProxy.balance, newProxyBefore + 0.2 ether);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzReplayKeysAreTracked(bytes32 replayKey) public {
        _seedEpochWithPositions();

        vm.prank(callbackProxy);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 120e18, 100e18, replayKey);
        assertTrue(executor.processedReplayKeys(replayKey));

        vm.prank(callbackProxy);
        executor.settleEpoch(reactVmId, POOL_ID, 1, 120e18, 100e18, replayKey);
        assertTrue(executor.processedReplayKeys(replayKey));
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzInvalidReactVmReverts(address unexpectedVm) public {
        vm.assume(unexpectedVm != reactVmId);
        _seedEpochWithPositions();

        vm.prank(callbackProxy);
        vm.expectRevert(SettlementExecutor.InvalidReactVmId.selector);
        executor.settleEpoch(unexpectedVm, POOL_ID, 1, 120e18, 100e18, keccak256(abi.encode(unexpectedVm)));
    }

    function _seedEpochWithPositions() internal {
        vm.prank(alice);
        market.openPosition(POOL_ID, true, 20e18);
        vm.prank(bob);
        market.openPosition(POOL_ID, false, 20e18);
        vm.warp(block.timestamp + 1 days + 1);
    }
}
