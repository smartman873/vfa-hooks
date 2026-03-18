// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {EncodingLibrary} from "../../src/libraries/EncodingLibrary.sol";

contract EncodingLibraryTest is Test {
    function testShareTokenIdDiffersByDirection() public pure {
        bytes32 poolId = keccak256("pool-a");
        uint256 longId = EncodingLibrary.shareTokenId(poolId, 1, true);
        uint256 shortId = EncodingLibrary.shareTokenId(poolId, 1, false);

        assertTrue(longId != shortId);
    }

    function testReplayKeyMatchesExpectedHash() public pure {
        bytes32 poolId = keccak256("pool-b");
        bytes32 key = EncodingLibrary.replayKey(poolId, 10, 150e18, 100e18, 1_234_567, 42);
        bytes32 expected = keccak256(abi.encode(poolId, 10, 150e18, 100e18, 1_234_567, 42));
        assertEq(key, expected);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzReplayKeyDeterministic(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        uint256 sourceBlock,
        uint256 sourceLogIndex
    ) public pure {
        bytes32 a =
            EncodingLibrary.replayKey(poolId, epochId, realizedVolatility, settlementPrice, sourceBlock, sourceLogIndex);
        bytes32 b =
            EncodingLibrary.replayKey(poolId, epochId, realizedVolatility, settlementPrice, sourceBlock, sourceLogIndex);
        assertEq(a, b);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzReplayKeyChangesWhenInputChanges(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        uint256 sourceBlock,
        uint256 sourceLogIndex
    ) public {
        vm.assume(sourceLogIndex < type(uint256).max);

        bytes32 a =
            EncodingLibrary.replayKey(poolId, epochId, realizedVolatility, settlementPrice, sourceBlock, sourceLogIndex);
        bytes32 b = EncodingLibrary.replayKey(
            poolId, epochId, realizedVolatility, settlementPrice, sourceBlock, sourceLogIndex + 1
        );
        assertTrue(a != b);
    }
}
