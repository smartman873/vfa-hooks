// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {VolatilityMath} from "../../src/libraries/VolatilityMath.sol";

contract VolatilityMathTest is Test {
    function testComputeReturnsZeroWhenNoSwaps() public pure {
        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 1e18,
            spikeScale: 1e18,
            maxVolumeBoost: 2e18,
            maxSpikeBoost: 2e18
        });

        uint256 realized = VolatilityMath.computeRealizedVolatility(0, 0, 0, 0, 0, params);
        assertEq(realized, 0);
    }

    function testComputeDeterministicPositiveOutput() public pure {
        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 10_000e18,
            spikeScale: 100e18,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 1e18
        });

        uint256 realizedA = VolatilityMath.computeRealizedVolatility(100, 12_000, 10, 5_000e18, 50e18, params);
        uint256 realizedB = VolatilityMath.computeRealizedVolatility(100, 12_000, 10, 5_000e18, 50e18, params);

        assertGt(realizedA, 0);
        assertEq(realizedA, realizedB);
    }

    function testComputeAppliesBoostCaps() public pure {
        VolatilityMath.Params memory params = VolatilityMath.Params({
            volumeScale: 1,
            spikeScale: 1,
            maxVolumeBoost: 1e18,
            maxSpikeBoost: 2e18
        });

        uint256 realized = VolatilityMath.computeRealizedVolatility(500, 100_000, 20, type(uint128).max, type(uint128).max, params);
        assertGt(realized, 0);
    }
}
