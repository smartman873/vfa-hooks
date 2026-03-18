// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";

import {ReactiveVolatilityMath} from "./libraries/ReactiveVolatilityMath.sol";

contract VolatilityReactive is AbstractReactive {
    using ReactiveVolatilityMath for ReactiveVolatilityMath.Params;

    bytes32 internal constant EPOCH_STARTED_TOPIC_0 =
        keccak256("EpochStarted(bytes32,uint256,uint64,uint64,uint256)");
    bytes32 internal constant TELEMETRY_TOPIC_0 =
        keccak256("TelemetryUpdated(bytes32,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256)");

    struct TelemetrySnapshot {
        uint256 cumulativeAbsTickDelta;
        uint256 cumulativeSquaredTickDelta;
        uint256 cumulativeVolume;
        uint256 swapCount;
        uint256 volumeSpikeScore;
        uint256 lastTimestamp;
        uint256 lastBlockNumber;
    }

    struct EpochState {
        uint256 epochId;
        uint64 endTime;
        uint256 settlementPrice;
        uint256 startAbsTickDelta;
        uint256 startSquaredTickDelta;
        uint256 startVolume;
        uint256 startSwapCount;
        uint256 startSpikeScore;
        bool active;
        bool callbackSent;
    }

    event EpochTrackingUpdated(bytes32 indexed poolId, uint256 indexed epochId, uint64 endTime, uint256 settlementPrice);
    event EpochSettlementCallbackPrepared(
        bytes32 indexed poolId,
        uint256 indexed epochId,
        uint256 realizedVolatility,
        uint256 settlementPrice,
        bytes32 replayKey
    );
    event SubscriptionsInitialized(uint256 indexed originChainId, address indexed originHook, address indexed originMarket);

    address public immutable owner;
    uint64 internal constant MIN_CALLBACK_GAS_LIMIT = 100_000;
    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable originHook;
    address public immutable originMarket;
    address public immutable settlementExecutor;
    uint64 public immutable callbackGasLimit;
    bool public subscriptionsInitialized;

    ReactiveVolatilityMath.Params public modelParams;

    mapping(bytes32 => TelemetrySnapshot) public latestTelemetry;
    mapping(bytes32 => EpochState) public trackedEpochs;

    constructor(
        uint256 _originChainId,
        uint256 _destinationChainId,
        address _originHook,
        address _originMarket,
        address _settlementExecutor,
        uint64 _callbackGasLimit,
        ReactiveVolatilityMath.Params memory _modelParams
    ) payable {
        require(_callbackGasLimit >= MIN_CALLBACK_GAS_LIMIT, "callback gas too low");
        owner = msg.sender;
        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        originHook = _originHook;
        originMarket = _originMarket;
        settlementExecutor = _settlementExecutor;
        callbackGasLimit = _callbackGasLimit;
        modelParams = _modelParams;

        if (!vm) {
            _initializeSubscriptions();
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner only");
        _;
    }

    function initializeSubscriptions() external rnOnly onlyOwner {
        if (subscriptionsInitialized) {
            return;
        }
        _initializeSubscriptions();
    }

    function _initializeSubscriptions() internal {
        service.subscribe(
            originChainId,
            originHook,
            uint256(TELEMETRY_TOPIC_0),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        service.subscribe(
            originChainId,
            originMarket,
            uint256(EPOCH_STARTED_TOPIC_0),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        subscriptionsInitialized = true;
        emit SubscriptionsInitialized(originChainId, originHook, originMarket);
    }

    function react(IReactive.LogRecord calldata log) external vmOnly {
        if (log.topic_0 == uint256(EPOCH_STARTED_TOPIC_0) && log._contract == originMarket) {
            _handleEpochStarted(log);
            return;
        }

        if (log.topic_0 == uint256(TELEMETRY_TOPIC_0) && log._contract == originHook) {
            _handleTelemetry(log);
            return;
        }
    }

    function _handleEpochStarted(IReactive.LogRecord calldata log) internal {
        bytes32 poolId = bytes32(log.topic_1);
        uint256 epochId = log.topic_2;
        (, uint64 endTime, uint256 settlementPrice) = abi.decode(log.data, (uint64, uint64, uint256));

        TelemetrySnapshot storage snapshot = latestTelemetry[poolId];
        EpochState storage epochState = trackedEpochs[poolId];

        epochState.epochId = epochId;
        epochState.endTime = endTime;
        epochState.settlementPrice = settlementPrice;
        epochState.startAbsTickDelta = snapshot.cumulativeAbsTickDelta;
        epochState.startSquaredTickDelta = snapshot.cumulativeSquaredTickDelta;
        epochState.startVolume = snapshot.cumulativeVolume;
        epochState.startSwapCount = snapshot.swapCount;
        epochState.startSpikeScore = snapshot.volumeSpikeScore;
        epochState.active = true;
        epochState.callbackSent = false;

        emit EpochTrackingUpdated(poolId, epochId, endTime, settlementPrice);
    }

    function _handleTelemetry(IReactive.LogRecord calldata log) internal {
        bytes32 poolId = bytes32(log.topic_1);

        (
            ,
            uint256 cumulativeAbsTickDelta,
            uint256 cumulativeSquaredTickDelta,
            uint256 cumulativeVolume,
            uint256 swapCount,
            uint256 volumeSpikeScore,
            uint256 telemetryTimestamp,
            uint256 telemetryBlock
        ) = abi.decode(log.data, (int24, uint256, uint256, uint256, uint256, uint256, uint256, uint256));

        _updateTelemetrySnapshot(
            poolId,
            cumulativeAbsTickDelta,
            cumulativeSquaredTickDelta,
            cumulativeVolume,
            swapCount,
            volumeSpikeScore,
            telemetryTimestamp,
            telemetryBlock
        );

        _maybeEmitSettlementCallback(poolId, telemetryTimestamp, telemetryBlock, log.log_index);
    }

    function _updateTelemetrySnapshot(
        bytes32 poolId,
        uint256 cumulativeAbsTickDelta,
        uint256 cumulativeSquaredTickDelta,
        uint256 cumulativeVolume,
        uint256 swapCount,
        uint256 volumeSpikeScore,
        uint256 telemetryTimestamp,
        uint256 telemetryBlock
    ) internal {
        TelemetrySnapshot storage snapshot = latestTelemetry[poolId];
        snapshot.cumulativeAbsTickDelta = cumulativeAbsTickDelta;
        snapshot.cumulativeSquaredTickDelta = cumulativeSquaredTickDelta;
        snapshot.cumulativeVolume = cumulativeVolume;
        snapshot.swapCount = swapCount;
        snapshot.volumeSpikeScore = volumeSpikeScore;
        snapshot.lastTimestamp = telemetryTimestamp;
        snapshot.lastBlockNumber = telemetryBlock;
    }

    function _maybeEmitSettlementCallback(bytes32 poolId, uint256 telemetryTimestamp, uint256 telemetryBlock, uint256 logIndex)
        internal
    {
        EpochState storage epochState = trackedEpochs[poolId];
        if (!epochState.active || epochState.callbackSent) {
            return;
        }

        if (telemetryTimestamp < epochState.endTime) {
            return;
        }

        TelemetrySnapshot storage snapshot = latestTelemetry[poolId];

        uint256 absTickDelta = snapshot.cumulativeAbsTickDelta - epochState.startAbsTickDelta;
        uint256 squaredTickDelta = snapshot.cumulativeSquaredTickDelta - epochState.startSquaredTickDelta;
        uint256 volume = snapshot.cumulativeVolume - epochState.startVolume;
        uint256 swapDelta = snapshot.swapCount - epochState.startSwapCount;
        uint256 spikes = snapshot.volumeSpikeScore - epochState.startSpikeScore;

        uint256 realizedVolatility = ReactiveVolatilityMath.compute(
            absTickDelta,
            squaredTickDelta,
            swapDelta,
            volume,
            spikes,
            modelParams
        );

        bytes32 replayKey =
            keccak256(abi.encode(poolId, epochState.epochId, realizedVolatility, epochState.settlementPrice, telemetryBlock, logIndex));

        bytes memory payload = abi.encodeWithSignature(
            "settleEpoch(address,bytes32,uint256,uint256,uint256,bytes32)",
            address(0),
            poolId,
            epochState.epochId,
            realizedVolatility,
            epochState.settlementPrice,
            replayKey
        );

        epochState.callbackSent = true;

        emit EpochSettlementCallbackPrepared(
            poolId,
            epochState.epochId,
            realizedVolatility,
            epochState.settlementPrice,
            replayKey
        );
        emit Callback(destinationChainId, settlementExecutor, callbackGasLimit, payload);
    }
}
