# Deployment

## Bootstrap

```bash
./scripts/bootstrap.sh
```

This installs shared dependencies and pins Uniswap v4 repos to commit prefix `3779387`.

## Local

```bash
make deploy-local
```

## Origin Testnet (Unichain Sepolia Example)

Required environment variables:

- `SEPOLIA_RPC_URL`
- `SEPOLIA_PRIVATE_KEY`
- `CALLBACK_PROXY_ADDRESS`
- `EXPECTED_REACT_VM_ID` (recommended explicit) or `REACTIVE_PRIVATE_KEY` / `OWNER_ADDRESS` for auto-derivation

Then run:

```bash
make deploy-sepolia
```

Published deployments are tracked in:

- `docs/deployments.testnet.json` (machine-readable)
- `docs/deployed-addresses.md` (human-readable)

## Reactive (Lasna/Mainnet)

Required environment variables:

- `REACTIVE_RPC_URL`
- `REACTIVE_PRIVATE_KEY`
- `SYSTEM_CONTRACT_ADDR` (default `0x0000000000000000000000000000000000fffFfF`)

Then run:

```bash
make deploy-reactive
```

## Live E2E Using Published Addresses

```bash
make demo-testnet-live
```

By default, this command reuses addresses from `docs/deployments.testnet.json`.
Use `FORCE_REDEPLOY=1` to refresh all deployments.

Settlement behavior:

- `SETTLEMENT_MODE=reactive` is the default and waits for callback-driven settlement.
- `SETTLEMENT_MODE=manual` is available for explicit simulation/emergency workflows.
- `ALLOW_MANUAL_FALLBACK=1` allows fallback to manual settlement only after reactive timeout.

## Known Callback Proxy Addresses (from local context)

- Ethereum Sepolia: `0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA`
- Base Sepolia: `0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6`
- Unichain Sepolia: `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4`
- Reactive Lasna/Mainnet: `0x0000000000000000000000000000000000fffFfF`
