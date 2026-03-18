# VFA Hook Specification

## 1. Objective

Design a deterministic, on-chain volatility derivatives primitive where users trade long/short volatility exposure instead of directional spot price.

Core design constraints:

- Uniswap v4 hook semantics and permission bits must be correct.
- Reactive Network is used for autonomous epoch completion and destination callbacks.
- Settlement must be authenticated, replay-safe, and idempotent.

## 2. System Components

### 2.1 Origin Chain

- `VolatilityHook` (Uniswap v4 hook)
- `VolatilityMarket` (epoch/position accounting)
- `VolatilityShareToken` (tokenized epoch-side position receipts)

### 2.2 Reactive Network

- `VolatilityReactive` subscribes via `subscribe(...)` to origin telemetry + epoch lifecycle events.
- `react(LogRecord)` updates local ReactVM state and emits `Callback(...)` payloads.

### 2.3 Destination Chain

- `SettlementExecutor` receives callback where first payload arg is overwritten by ReactVM ID.
- Executor validates callback proxy sender and expected ReactVM ID.
- Executor finalizes epoch on `VolatilityMarket`.

## 3. Data Model

### 3.1 VolatilityPool

```solidity
struct VolatilityPool {
    bytes32 poolId;
    uint64 epochDuration;
    uint64 minTradeSize;
    uint64 maxTradeSize;
    uint256 baselineVolatility;
    uint256 currentEpochId;
    bool exists;
}
```

### 3.2 Epoch

```solidity
struct Epoch {
    uint64 startTime;
    uint64 endTime;
    uint256 realizedVolatility;
    uint256 settlementPrice;
    uint256 totalLong;
    uint256 totalShort;
    bool settled;
}
```

### 3.3 Position

```solidity
struct Position {
    address owner;
    bytes32 poolId;
    uint256 epochId;
    uint256 amount;
    bool isLong;
    bool closed;
    bool claimed;
}
```

## 4. Volatility Metric

Telemetry is captured from swap hooks and modeled deterministically.

Let `d_i = tick_i - tick_{i-1}` for accepted swaps in an epoch.

- Absolute movement sum: `A = Σ |d_i|`
- Squared movement sum: `Q = Σ d_i^2`
- Accepted swap count: `N`
- Volume sum: `V = Σ volume_i`
- Volume spike score: `S` (event-count weighted by EMA deviation)

Mean absolute move:

`μ = A / max(N,1)`

Variance proxy:

`var = max(Q / max(N,1) - μ^2, 0)`

Base volatility:

`σ_base = sqrt(var) * 1e18`

Volume multiplier:

`m_v = 1e18 + min((V * 1e18) / volumeScale, maxVolumeBoost)`

Spike multiplier:

`m_s = 1e18 + min((S * 1e18) / spikeScale, maxSpikeBoost)`

Final realized volatility:

`σ_realized = σ_base * m_v / 1e18 * m_s / 1e18`

All parameters are deterministic constants/config values, no offchain oracle.

## 5. Payout Function

The epoch strike/settlement reference is `K` (stored as `epoch.settlementPrice`).

- If `σ_realized > K`: long side wins.
- If `σ_realized < K`: short side wins.
- If equal: flat outcome.

Parimutuel redistribution:

- Winners receive principal + pro-rata share of losing side collateral.
- Losers receive zero beyond any pre-close collateral already withdrawn.

This guarantees solvency by construction.

## 6. Hook Requirements Mapping

From Uniswap v4 docs (`IHooks`, `Hooks`, `BaseHook`):

- Hook permission bits are encoded in hook address low bits.
- `PoolManager` decides hook invocation.
- Hook entrypoints are `onlyPoolManager` via `BaseHook`.
- `beforeSwap` and `afterSwap` are implemented.
- `PoolKey`, `PoolId`, `StateLibrary.getSlot0` are used.

## 7. Reactive Requirements Mapping

From Reactive docs (`IReactive`, `ISubscriptionService`, callbacks):

- Subscription by `service.subscribe(chain_id, contract, topic_0,...topic_3)`.
- Event handling through `react(LogRecord)`.
- Settlement trigger by emitting `Callback(chain_id, contract, gas_limit, payload)`.
- First callback argument is overwritten with ReactVM ID by Reactive infra.
- Destination callback authenticates callback proxy and ReactVM ID.

## 8. Security Model

### Trust Boundaries

- Uniswap `PoolManager` trusted as canonical hook caller.
- Reactive callback proxy trusted only when sender + ReactVM checks pass.
- Reactive computed payload trusted after authentication.

### Required Controls

- callback authenticity validation (`msg.sender == callbackProxy`)
- ReactVM ID validation (`reactVmId == expectedRvmId`)
- replay protection (`processed[replayKey]`)
- settlement idempotency (`epoch.settled` guard)
- reentrancy guard in market and executor
- bounds checks on volatility and trade size
- anti-gaming filters on micro-swaps + extreme outlier tick deltas

### Not Guaranteed

- Full resistance to economic manipulation by capital-rich adversaries.
- Perfect fair pricing under pathological liquidity conditions.

## 9. Lifecycle

1. Pool initialized; epoch starts in `VolatilityMarket`.
2. Traders open long/short positions.
3. Swaps occur in Uniswap v4 pool; hook emits telemetry.
4. `VolatilityReactive` processes logs and detects epoch expiry.
5. Reactive emits settlement callback payload.
6. `SettlementExecutor` authenticates and finalizes epoch.
7. Users claim payout or re-enter next epoch.

## 10. Assumptions / TBD

- Source-of-truth callback proxy addresses are pulled from local `context` docs.
- Single settlement collateral token per market instance.
- Telemetry sampling quality depends on observed swap flow.
- Cross-chain delay between origin telemetry and destination callback is non-zero.
- Commit pinset ID `3779387` is mapped to fixed v4-core/periphery commits in `scripts/bootstrap.sh`.
