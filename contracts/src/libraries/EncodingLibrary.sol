// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library EncodingLibrary {
    function shareTokenId(bytes32 poolId, uint256 epochId, bool isLong) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(poolId, epochId, isLong)));
    }

    function replayKey(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        uint256 sourceBlock,
        uint256 sourceLogIndex
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(poolId, epochId, realizedVolatility, settlementPrice, sourceBlock, sourceLogIndex));
    }
}
