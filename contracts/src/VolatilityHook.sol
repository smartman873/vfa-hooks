// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract VolatilityHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    struct Telemetry {
        int24 lastTick;
        bool seeded;
        uint256 cumulativeAbsTickDelta;
        uint256 cumulativeSquaredTickDelta;
        uint256 cumulativeVolume;
        uint256 swapCount;
        uint256 volumeSpikeScore;
        uint256 emaVolume;
        uint256 lastVolume;
        uint256 lastUpdateBlock;
        uint256 lastUpdateTimestamp;
    }

    event TelemetryUpdated(
        bytes32 indexed poolId,
        int24 tick,
        uint256 cumulativeAbsTickDelta,
        uint256 cumulativeSquaredTickDelta,
        uint256 cumulativeVolume,
        uint256 swapCount,
        uint256 volumeSpikeScore,
        uint256 timestamp,
        uint256 blockNumber
    );

    event TelemetrySkipped(bytes32 indexed poolId, uint256 volume, uint8 reason);

    uint256 public immutable minSwapVolume;
    uint24 public immutable maxTickDelta;

    mapping(bytes32 => Telemetry) private telemetryByPool;
    mapping(bytes32 => int24) private pendingTickBeforeSwap;
    mapping(bytes32 => uint256) private pendingSwapVolume;

    constructor(IPoolManager _poolManager, uint256 _minSwapVolume, uint24 _maxTickDelta) BaseHook(_poolManager) {
        require(_maxTickDelta > 0, "invalid maxTickDelta");
        minSwapVolume = _minSwapVolume;
        maxTickDelta = _maxTickDelta;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getTelemetry(bytes32 poolId) external view returns (Telemetry memory) {
        return telemetryByPool[poolId];
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());

        (, int24 tick,,) = poolManager.getSlot0(key.toId());
        pendingTickBeforeSwap[poolId] = tick;

        uint256 volume = _absInt256(params.amountSpecified);
        if (volume < minSwapVolume) {
            pendingSwapVolume[poolId] = 0;
            emit TelemetrySkipped(poolId, volume, 1);
        } else {
            pendingSwapVolume[poolId] = volume;
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        uint256 volume = pendingSwapVolume[poolId];

        (, int24 postTick,,) = poolManager.getSlot0(key.toId());
        Telemetry storage telemetry = telemetryByPool[poolId];

        if (!telemetry.seeded) {
            telemetry.lastTick = postTick;
            telemetry.seeded = true;
        }

        if (volume == 0) {
            telemetry.lastTick = postTick;
            telemetry.lastUpdateBlock = block.number;
            telemetry.lastUpdateTimestamp = block.timestamp;
            return (BaseHook.afterSwap.selector, 0);
        }

        int24 preTick = pendingTickBeforeSwap[poolId];
        uint256 tickDelta = _absTickDelta(preTick, postTick);
        if (tickDelta > maxTickDelta) {
            tickDelta = maxTickDelta;
            emit TelemetrySkipped(poolId, volume, 2);
        }

        telemetry.cumulativeAbsTickDelta += tickDelta;
        telemetry.cumulativeSquaredTickDelta += tickDelta * tickDelta;
        telemetry.cumulativeVolume += volume;
        telemetry.swapCount += 1;

        if (telemetry.emaVolume == 0) {
            telemetry.emaVolume = volume;
        } else {
            telemetry.emaVolume = (telemetry.emaVolume * 7 + volume * 3) / 10;
        }

        if (telemetry.emaVolume > 0 && volume > telemetry.emaVolume * 2) {
            telemetry.volumeSpikeScore += (volume * 1e18) / telemetry.emaVolume;
        }

        telemetry.lastVolume = volume;
        telemetry.lastTick = postTick;
        telemetry.lastUpdateBlock = block.number;
        telemetry.lastUpdateTimestamp = block.timestamp;

        emit TelemetryUpdated(
            poolId,
            postTick,
            telemetry.cumulativeAbsTickDelta,
            telemetry.cumulativeSquaredTickDelta,
            telemetry.cumulativeVolume,
            telemetry.swapCount,
            telemetry.volumeSpikeScore,
            block.timestamp,
            block.number
        );

        delete pendingSwapVolume[poolId];
        delete pendingTickBeforeSwap[poolId];

        return (BaseHook.afterSwap.selector, 0);
    }

    function _absInt256(int256 x) private pure returns (uint256) {
        if (x >= 0) {
            return uint256(x);
        }
        return uint256(-x);
    }

    function _absTickDelta(int24 a, int24 b) private pure returns (uint256) {
        int256 diff = int256(a) - int256(b);
        if (diff >= 0) {
            return uint256(diff);
        }
        return uint256(-diff);
    }
}
