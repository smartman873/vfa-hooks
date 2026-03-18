# Security

## Primary Threats

- Callback forgery
- Replay of old settlement payloads
- Double settlement for same epoch
- Reentrancy on claim/close
- Telemetry manipulation with dust swaps
- Out-of-bound settlement inputs

## Mitigations

- `msg.sender == callbackProxy`
- `reactVmId == expectedReactVmId` (non-zero expected ID enforced at deployment and setter level)
- `processedReplayKeys[replayKey]` replay guard
- `epoch.settled` idempotency checks
- `ReentrancyGuard` on stateful external methods
- minimum trade notional and tick-delta clamp
- strict bounds checks on realized volatility and epoch params
- callback debt settlement hooks via `pay(uint256)` / `coverDebt()` support on destination executor

## Residual Risks

- Economic manipulation remains possible under extreme liquidity asymmetry
- Cross-domain message delay can affect user expectations
- Destination-chain liveness impacts settlement timing

## Operational Guidance

- Monitor callback failures and debt balances
- Keep emergency pause and owner roles under multisig
- Add independent audits prior to production capital
