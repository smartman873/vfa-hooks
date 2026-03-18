// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IVolatilityMarket {
    function finalizeEpoch(
        bytes32 poolId,
        uint256 epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        bytes32 replayKey
    ) external;

    function isEpochSettled(bytes32 poolId, uint256 epochId) external view returns (bool);
}
