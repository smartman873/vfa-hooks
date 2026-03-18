# Testing

## Contracts

```bash
cd contracts
forge build
forge test --offline
forge coverage --offline --exclude-tests --no-match-coverage "script|test|lib|deps"
```

Test scope:

- volatility math correctness
- epoch transitions
- settlement payout logic
- callback authentication/replay checks
- integration path with v4 swap telemetry + settlement flow

## Reactive

```bash
cd reactive
forge build
forge test --offline
forge coverage --offline --exclude-tests --no-match-coverage "script|test|lib|deps"
```

Covers:

- subscriptions
- log decoding
- callback payload construction
- idempotent trigger behavior

## Frontend

```bash
cd frontend
pnpm install
pnpm build
```
