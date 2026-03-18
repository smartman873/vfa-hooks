// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ReactiveVolatilityMath} from "../src/libraries/ReactiveVolatilityMath.sol";

contract ReactiveVolatilityMathTest is Test {
    function testComputeReturnsZeroWhenNoSwaps() public pure {
        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: 1e18,
            spikeScale: 1e18,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 1e18
        });

        uint256 value = ReactiveVolatilityMath.compute(100, 1000, 0, 1, 1, params);
        assertEq(value, 0);
    }

    function testComputeReturnsZeroWhenVarianceIsNotPositive() public pure {
        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: 1e18,
            spikeScale: 1e18,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 1e18
        });

        // meanAbs = 10, meanAbsSquared = 100, averageSquared = 100.
        uint256 value = ReactiveVolatilityMath.compute(20, 200, 2, 0, 0, params);
        assertEq(value, 0);
    }

    function testComputeAppliesScaleFallbacksAndBoostCaps() public pure {
        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: 0,
            spikeScale: 0,
            maxVolumeBoost: 2e18,
            maxSpikeBoost: 3e18
        });

        // variance = (10000/4) - (100/4)^2 = 2500 - 625 = 1875, sqrt = 43
        uint256 value = ReactiveVolatilityMath.compute(100, 10_000, 4, 10e18, 10e18, params);
        assertEq(value, 516e18);
    }

    function testComputeLeavesBoostUncappedWhenBelowLimits() public pure {
        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: 100e18,
            spikeScale: 100e18,
            maxVolumeBoost: 10e18,
            maxSpikeBoost: 10e18
        });

        uint256 value = ReactiveVolatilityMath.compute(100, 10_000, 4, 1e18, 1e18, params);

        uint256 base = ReactiveVolatilityMath.sqrt(1875) * 1e18;
        uint256 volumeBoost = (1e18 * 1e18) / 100e18;
        uint256 spikeBoost = (1e18 * 1e18) / 100e18;
        uint256 weighted = (base * (1e18 + volumeBoost)) / 1e18;
        uint256 expected = (weighted * (1e18 + spikeBoost)) / 1e18;

        assertEq(value, expected);
    }

    function testSqrtHandlesZeroAndHighThresholdPath() public pure {
        assertEq(ReactiveVolatilityMath.sqrt(0), 0);

        uint256 large = uint256(1) << 255;
        uint256 root = ReactiveVolatilityMath.sqrt(large);

        assertGt(root, 0);
        assertLe(root, large / root);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzSqrtFloorProperty(uint256 x) public pure {
        uint256 root = ReactiveVolatilityMath.sqrt(x);
        if (root == 0) {
            assertEq(x, 0);
            return;
        }

        assertLe(root, x / root);
        uint256 next = root + 1;
        assertGt(next, x / next);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzzComputeDeterministic(
        uint64 absTickDeltaSum,
        uint64 squaredTickDeltaSum,
        uint64 swapCountRaw,
        uint128 cumulativeVolume,
        uint128 spikeScore
    ) public pure {
        uint256 swapCount = uint256(swapCountRaw % 1_000);
        ReactiveVolatilityMath.Params memory params = ReactiveVolatilityMath.Params({
            volumeScale: 10_000e18,
            spikeScale: 100e18,
            maxVolumeBoost: 2e18,
            maxSpikeBoost: 2e18
        });

        uint256 first = ReactiveVolatilityMath.compute(
            uint256(absTickDeltaSum),
            uint256(squaredTickDeltaSum),
            swapCount,
            uint256(cumulativeVolume),
            uint256(spikeScore),
            params
        );
        uint256 second = ReactiveVolatilityMath.compute(
            uint256(absTickDeltaSum),
            uint256(squaredTickDeltaSum),
            swapCount,
            uint256(cumulativeVolume),
            uint256(spikeScore),
            params
        );

        assertEq(first, second);
    }
}

