# Demo

## Local Demo

```bash
make demo-local
```

Expected lifecycle:

1. Deploy hook + market + executor
2. Create pool and start epoch
3. Open long and short positions
4. Execute swaps to produce telemetry
5. Trigger settlement (Reactive callback path in integration tests; optional simulation path for deterministic local runs)
6. Claim payouts

## Live Testnet E2E (Reuses Deployed Addresses)

```bash
make demo-testnet-live
```

Default behavior:

1. Reads deployed addresses from `docs/deployments.testnet.json`
2. Executes live lifecycle transactions against those addresses
3. Waits for Reactive callback-based settlement (`SETTLEMENT_MODE=reactive`)
4. Fails if no callback settlement arrives within timeout unless manual fallback is explicitly enabled
5. Prints origin-chain + Reactive Lasna tx URLs (for the current configured chain IDs)
6. Updates:
   - `docs/deployments.testnet.json`
   - `docs/deployed-addresses.md`

Manual settlement mode (explicit):

```bash
SETTLEMENT_MODE=manual make demo-testnet-live
```

Reactive mode with manual fallback after timeout:

```bash
ALLOW_MANUAL_FALLBACK=1 make demo-testnet-live
```

Reactive callback requirement:

- At least one `TelemetryUpdated` event must be emitted after epoch end (for example, a swap on a hooked v4 pool) so `VolatilityReactive` can emit callback settlement.

Force a fresh redeploy before lifecycle:

```bash
FORCE_REDEPLOY=1 make demo-testnet-live
```

Custom callback wait tuning:

```bash
SETTLEMENT_TIMEOUT_SECONDS=600 SETTLEMENT_POLL_INTERVAL_SECONDS=10 make demo-testnet-live
```

Previous behavior:

- deterministic manual settlement was the default lifecycle path
- now it is opt-in only

## Sepolia Deploy-Only Demo

```bash
make demo-sepolia
```

This is an alias of `make demo-testnet-live`.

## Frontend Demo

```bash
cd frontend
pnpm install
pnpm dev
```

Open the app and use the dashboard timeline to inspect epochs, positions, and settlement states.
