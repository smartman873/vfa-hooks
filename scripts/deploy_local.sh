#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${POOL_MANAGER:-}" ]]; then
  echo "error: POOL_MANAGER is required for local deployment" >&2
  exit 1
fi

RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

cd contracts
forge script script/deploy/DeployLocal.s.sol:DeployLocalScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
