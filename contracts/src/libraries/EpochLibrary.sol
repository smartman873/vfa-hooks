// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library EpochLibrary {
    function isActive(uint64 startTime, uint64 endTime, bool settled, uint256 timestamp)
        internal
        pure
        returns (bool)
    {
        return timestamp >= startTime && timestamp < endTime && !settled;
    }

    function hasEnded(uint64 endTime, uint256 timestamp) internal pure returns (bool) {
        return timestamp >= endTime;
    }
}
