// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "../utils/libraries/EasyPosm.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {VolatilityHook} from "../../src/VolatilityHook.sol";

contract VolatilityHookEdgeCasesTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    bytes32 internal constant TELEMETRY_SKIPPED_TOPIC = keccak256("TelemetrySkipped(bytes32,uint256,uint8)");

    Currency internal currency0;
    Currency internal currency1;
    PoolKey internal poolKey;
    VolatilityHook internal hook;
    uint256 internal tokenId;

    function testConstructorRejectsZeroMaxTickDelta() public {
        deployArtifactsAndLabel();
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (uint160(0x7777) << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager, 1, 0);

        vm.expectRevert(bytes("invalid maxTickDelta"));
        deployCodeTo("VolatilityHook.sol:VolatilityHook", constructorArgs, flags);
    }

    function testLowVolumeSwapSkipsTelemetryAggregation() public {
        _deployPoolAndHook(2e18, 500);

        vm.recordLogs();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(_containsSkipReason(logs, 1));

        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        VolatilityHook.Telemetry memory telemetry = hook.getTelemetry(poolId);
        assertEq(telemetry.swapCount, 0);
        assertEq(telemetry.cumulativeVolume, 0);
        assertTrue(telemetry.seeded);
        assertGt(telemetry.lastUpdateBlock, 0);
        assertGt(telemetry.lastUpdateTimestamp, 0);
    }

    function testTickClampEmaUpdateSpikeAndSignedAmountPaths() public {
        _deployPoolAndHook(1, 1);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1e17,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        vm.recordLogs();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_containsSkipReason(logs, 2));

        // Exact-output swap forces positive amountSpecified in beforeSwap.
        swapRouter.swapTokensForExactTokens({
            amountOut: 1e16,
            amountInMax: 1e18,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Opposite direction covers absolute tick-delta branch where preTick < postTick.
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e16,
            amountOutMin: 0,
            zeroForOne: false,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        VolatilityHook.Telemetry memory telemetry = hook.getTelemetry(poolId);

        assertGt(telemetry.swapCount, 1);
        assertGt(telemetry.emaVolume, 0);
        assertGt(telemetry.volumeSpikeScore, 0);
        assertGt(telemetry.cumulativeAbsTickDelta, 0);
        assertGt(telemetry.cumulativeSquaredTickDelta, 0);
    }

    function _deployPoolAndHook(uint256 minSwapVolume, uint24 maxTickDelta) internal {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (uint160(0x7777) << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, minSwapVolume, maxTickDelta);
        deployCodeTo("VolatilityHook.sol:VolatilityHook", constructorArgs, flags);
        hook = VolatilityHook(flags);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
        assertGt(tokenId, 0);
    }

    function _containsSkipReason(Vm.Log[] memory logs, uint8 reason) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != TELEMETRY_SKIPPED_TOPIC) {
                continue;
            }

            (, uint8 decodedReason) = abi.decode(logs[i].data, (uint256, uint8));
            if (decodedReason == reason) {
                return true;
            }
        }

        return false;
    }
}
