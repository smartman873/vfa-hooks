// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library VolatilityMath {
    uint256 internal constant ONE = 1e18;

    struct Params {
        uint256 volumeScale;
        uint256 spikeScale;
        uint256 maxVolumeBoost;
        uint256 maxSpikeBoost;
    }

    function computeRealizedVolatility(
        uint256 absTickDeltaSum,
        uint256 squaredTickDeltaSum,
        uint256 swapCount,
        uint256 cumulativeVolume,
        uint256 spikeScore,
        Params memory params
    ) internal pure returns (uint256) {
        if (swapCount == 0) {
            return 0;
        }

        uint256 meanAbs = absTickDeltaSum / swapCount;
        uint256 meanAbsSquared = meanAbs * meanAbs;
        uint256 averageSquared = squaredTickDeltaSum / swapCount;

        if (averageSquared <= meanAbsSquared) {
            return 0;
        }

        uint256 variance = averageSquared - meanAbsSquared;
        uint256 baseVolatility = sqrt(variance) * ONE;

        uint256 volumeScale = params.volumeScale == 0 ? 1 : params.volumeScale;
        uint256 spikeScale = params.spikeScale == 0 ? 1 : params.spikeScale;

        uint256 volumeBoost = (cumulativeVolume * ONE) / volumeScale;
        if (volumeBoost > params.maxVolumeBoost) {
            volumeBoost = params.maxVolumeBoost;
        }

        uint256 spikeBoost = (spikeScore * ONE) / spikeScale;
        if (spikeBoost > params.maxSpikeBoost) {
            spikeBoost = params.maxSpikeBoost;
        }

        uint256 weightedVolatility = (baseVolatility * (ONE + volumeBoost)) / ONE;
        weightedVolatility = (weightedVolatility * (ONE + spikeBoost)) / ONE;

        return weightedVolatility;
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) {
            return 0;
        }

        uint256 xx = x;
        z = 1;

        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            z <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            z <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            z <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            z <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            z <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            z <<= 2;
        }
        if (xx >= 0x8) {
            z <<= 1;
        }

        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;
        z = (z + x / z) >> 1;

        uint256 y = x / z;
        return z < y ? z : y;
    }
}
