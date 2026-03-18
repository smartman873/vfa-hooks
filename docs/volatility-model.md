# Volatility Model

The protocol computes realized volatility from deterministic on-chain telemetry.

## Inputs

- Tick deltas between swaps
- Cumulative squared tick deltas
- Swap count
- Volume accumulation
- Volume-spike score

## Formula

Let `d_i` be tick deltas over accepted swaps.

- `A = Σ |d_i|`
- `Q = Σ d_i^2`
- `N = swap count`
- `V = cumulative volume`
- `S = spike score`

Compute:

- `μ = A / max(N,1)`
- `var = max(Q / max(N,1) - μ^2, 0)`
- `σ_base = sqrt(var) * 1e18`
- `m_v = 1e18 + min(V * 1e18 / volumeScale, maxVolumeBoost)`
- `m_s = 1e18 + min(S * 1e18 / spikeScale, maxSpikeBoost)`
- `σ_realized = σ_base * m_v / 1e18 * m_s / 1e18`

## Determinism and Gas

- No external oracle reads
- Integer math only
- O(1) updates per accepted swap
- Cumulative counters avoid per-swap arrays

## Anti-Gaming Filters

- Ignore sub-threshold swap notional
- Clamp extreme single-step tick jumps
- Track simple EMA-based volume spikes
