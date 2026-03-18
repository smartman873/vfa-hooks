// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {VolatilityMath} from "../../src/libraries/VolatilityMath.sol";

contract VolatilityMathAdvancedTest is Test {
    function testComputeReturnsZeroWhenVarianceIsZero() public pure {
        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 1e18,
            spikeScale: 1e18,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 1e18
        });

        uint256 realized = VolatilityMath.computeRealizedVolatility(100, 1_000, 10, 1e18, 1e18, params);
        assertEq(realized, 0);
    }

    function testSqrtHandlesThresholdBranches() public pure {
        _assertSqrtBounded(0);
        _assertSqrtBounded(8);
        _assertSqrtBounded(0x10);
        _assertSqrtBounded(0x100);
        _assertSqrtBounded(0x10000);
        _assertSqrtBounded(0x100000000);
        _assertSqrtBounded(0x10000000000000000);
        _assertSqrtBounded(0x100000000000000000000000000000000);
        _assertSqrtBounded(uint256(type(uint128).max) * uint256(type(uint128).max));
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzSqrtFloorProperty(uint256 x) public pure {
        _assertSqrtBounded(x);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzComputeDeterministic(
        uint64 swapCountRaw,
        uint64 meanAbsRaw,
        uint64 varianceRaw,
        uint128 cumulativeVolume,
        uint128 spikeScore
    ) public pure {
        uint256 swapCount = _boundU256(uint256(swapCountRaw), 1, 10_000);
        uint256 meanAbs = _boundU256(uint256(meanAbsRaw), 1, 1_000_000);
        uint256 variance = _boundU256(uint256(varianceRaw), 1, 1_000_000);

        uint256 absTickDeltaSum = meanAbs * swapCount;
        uint256 squaredTickDeltaSum = (meanAbs * meanAbs + variance) * swapCount;

        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 10_000e18,
            spikeScale: 100e18,
            maxVolumeBoost: 2e18,
            maxSpikeBoost: 2e18
        });

        uint256 a = VolatilityMath.computeRealizedVolatility(
            absTickDeltaSum, squaredTickDeltaSum, swapCount, cumulativeVolume, spikeScore, params
        );
        uint256 b = VolatilityMath.computeRealizedVolatility(
            absTickDeltaSum, squaredTickDeltaSum, swapCount, cumulativeVolume, spikeScore, params
        );

        assertEq(a, b);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzComputeUsesUnitFallbackForZeroScales(
        uint64 swapCountRaw,
        uint64 meanAbsRaw,
        uint64 varianceRaw,
        uint128 cumulativeVolume,
        uint128 spikeScore
    ) public pure {
        uint256 swapCount = _boundU256(uint256(swapCountRaw), 1, 10_000);
        uint256 meanAbs = _boundU256(uint256(meanAbsRaw), 1, 1_000_000);
        uint256 variance = _boundU256(uint256(varianceRaw), 1, 1_000_000);

        uint256 absTickDeltaSum = meanAbs * swapCount;
        uint256 squaredTickDeltaSum = (meanAbs * meanAbs + variance) * swapCount;

        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 0,
            spikeScale: 0,
            maxVolumeBoost: 3e18,
            maxSpikeBoost: 3e18
        });

        uint256 realized = VolatilityMath.computeRealizedVolatility(
            absTickDeltaSum, squaredTickDeltaSum, swapCount, cumulativeVolume, spikeScore, params
        );

        assertGt(realized, 0);
    }

    function _assertSqrtBounded(uint256 x) internal pure {
        uint256 root = VolatilityMath.sqrt(x);
        if (x == 0) {
            assertEq(root, 0);
            return;
        }

        assertLe(root, x / root);

        uint256 next = root + 1;
        assertGt(next, x / next);
    }

    function _boundU256(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (x < min) {
            return min;
        }
        if (x > max) {
            return max;
        }
        return x;
    }
}
