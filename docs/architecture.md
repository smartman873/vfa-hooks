# Architecture

## Components

- `contracts/src/VolatilityHook.sol`
- `contracts/src/VolatilityMarket.sol`
- `contracts/src/SettlementExecutor.sol`
- `reactive/src/VolatilityReactive.sol`
- `frontend/` dashboard

## System Diagram

```mermaid
flowchart LR
  subgraph O[Origin]
    H[VolatilityHook]
    M[VolatilityMarket]
  end

  subgraph R[Reactive]
    VR[VolatilityReactive]
  end

  subgraph D[Destination]
    X[SettlementExecutor]
  end

  H -->|Telemetry events| VR
  M -->|Epoch events| VR
  VR -->|Callback payload| X
  X -->|finalizeEpoch| M
```

## Sequence

```mermaid
sequenceDiagram
  participant Trader
  participant Market
  participant Hook
  participant Reactive
  participant Executor

  Trader->>Market: openPosition
  Hook->>Reactive: VolatilityTelemetry
  Market->>Reactive: EpochStarted
  Reactive->>Executor: callback(rvm, payload)
  Executor->>Market: finalizeEpoch
  Trader->>Market: claim
```

## Component Interactions

```mermaid
graph TD
  PM[PoolManager] --> H[VolatilityHook]
  H --> R[VolatilityReactive]
  R --> X[SettlementExecutor]
  X --> M[VolatilityMarket]
  M --> S[VolatilityShareToken]
  S --> UI[Frontend]
```

## Key Constraints

- Hook entrypoints only callable by `PoolManager`.
- Hook permission bits must match deployment address bits.
- Reactive callback first argument is overwritten with ReactVM ID.
- Executor must validate callback proxy + ReactVM ID.
