// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {VolatilityShareToken} from "../../src/VolatilityShareToken.sol";

contract VolatilityShareTokenTest is Test {
    VolatilityShareToken internal share;

    address internal market = address(0xCAFE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant TOKEN_ID = 7;

    function setUp() public {
        share = new VolatilityShareToken("ipfs://share/{id}.json", address(this));
        share.setMarket(market);
    }

    function testSetMarketRejectsZeroAddress() public {
        vm.expectRevert("zero market");
        share.setMarket(address(0));
    }

    function testSetMarketOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        share.setMarket(address(0xABCD));
    }

    function testOnlyMarketCanMintAndBurn() public {
        vm.prank(alice);
        vm.expectRevert(VolatilityShareToken.OnlyMarket.selector);
        share.mint(alice, TOKEN_ID, 1);

        vm.prank(market);
        share.mint(alice, TOKEN_ID, 10);
        assertEq(share.balanceOf(alice, TOKEN_ID), 10);

        vm.prank(alice);
        vm.expectRevert(VolatilityShareToken.OnlyMarket.selector);
        share.burn(alice, TOKEN_ID, 1);

        vm.prank(market);
        share.burn(alice, TOKEN_ID, 4);
        assertEq(share.balanceOf(alice, TOKEN_ID), 6);
    }

    function testTransfersDisabledByDefault() public {
        vm.prank(market);
        share.mint(alice, TOKEN_ID, 10);

        vm.prank(alice);
        vm.expectRevert(VolatilityShareToken.TransfersDisabled.selector);
        share.safeTransferFrom(alice, bob, TOKEN_ID, 1, "");
    }

    function testTransfersCanBeEnabledByOwner() public {
        share.setTransfersEnabled(true);
        assertTrue(share.transfersEnabled());

        vm.prank(market);
        share.mint(alice, TOKEN_ID, 10);

        vm.prank(alice);
        share.safeTransferFrom(alice, bob, TOKEN_ID, 4, "");
        assertEq(share.balanceOf(alice, TOKEN_ID), 6);
        assertEq(share.balanceOf(bob, TOKEN_ID), 4);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzMarketMintBurnRoundTrip(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e18);

        vm.prank(market);
        share.mint(alice, TOKEN_ID, amount);
        assertEq(share.balanceOf(alice, TOKEN_ID), amount);

        vm.prank(market);
        share.burn(alice, TOKEN_ID, amount);
        assertEq(share.balanceOf(alice, TOKEN_ID), 0);
    }
}
