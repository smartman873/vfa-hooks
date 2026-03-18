# API

## VolatilityHook

- `getTelemetry(bytes32 poolId)`
- `beforeSwap(...)`
- `afterSwap(...)`

Events:

- `TelemetryUpdated(bytes32 poolId, int24 tick, uint256 cumulativeAbsDelta, uint256 cumulativeSquaredDelta, uint256 cumulativeVolume, uint256 swapCount, uint256 spikeScore)`

## VolatilityMarket

- `createVolatilityPool(...)`
- `openPosition(bytes32 poolId, bool isLong, uint256 amount)`
- `closePosition(uint256 positionId)`
- `finalizeEpoch(bytes32 poolId, uint256 epochId, uint256 realizedVolatility, uint256 settlementPrice)`
- `claim(uint256 positionId)`

Events:

- `EpochStarted`
- `EpochFinalized`
- `PositionOpened`
- `PositionClosed`
- `SettlementExecuted`

## SettlementExecutor

- `settleEpoch(address reactVmId, bytes32 poolId, uint256 epochId, uint256 realizedVolatility, uint256 settlementPrice, bytes32 replayKey)`
- `settleEpochManual(bytes32 poolId, uint256 epochId, uint256 realizedVolatility, uint256 settlementPrice, bytes32 replayKey)` (owner-only emergency path)
- `pay(uint256 amount)` (callback proxy/system payment hook)
- `coverDebt()`

## VolatilityReactive

- `react(LogRecord log)`
- `emit Callback(...)` when epoch maturity is detected
