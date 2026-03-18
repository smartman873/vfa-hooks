# Frontend

The frontend is a React + TypeScript dashboard consuming contracts through shared ABIs and constants.

## Features

- volatility chart
- epoch timeline
- position table
- PnL preview and settlement status

## Data Sources

- `shared/abis/*`
- `shared/constants/*`
- on-chain reads via public RPC

## Commands

```bash
cd frontend
pnpm install
pnpm dev
pnpm build
```
