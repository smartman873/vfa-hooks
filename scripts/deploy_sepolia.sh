#!/usr/bin/env bash
set -euo pipefail

POOL_MANAGER="${POOL_MANAGER:-${POOL_MANAGER_ADDRESS:-}}"
CALLBACK_PROXY_ADDRESS="${CALLBACK_PROXY_ADDRESS:-${DESTINATION_CALLBACK_PROXY_ADDR:-}}"
EXPECTED_REACT_VM_ID="${EXPECTED_REACT_VM_ID:-}"

if [[ -z "$EXPECTED_REACT_VM_ID" && -n "${REACTIVE_PRIVATE_KEY:-}" ]]; then
  if ! command -v cast >/dev/null 2>&1; then
    echo "error: cast is required to derive EXPECTED_REACT_VM_ID from REACTIVE_PRIVATE_KEY" >&2
    exit 1
  fi
  EXPECTED_REACT_VM_ID="$(cast wallet address --private-key "$REACTIVE_PRIVATE_KEY")"
fi

if [[ -z "$EXPECTED_REACT_VM_ID" && -n "${OWNER_ADDRESS:-}" ]]; then
  EXPECTED_REACT_VM_ID="$OWNER_ADDRESS"
fi

if [[ -z "${CALLBACK_PROXY_ADDRESS}" ]]; then
  case "${SEPOLIA_CHAIN_ID:-}" in
    84532)
      # Base Sepolia callback proxy.
      CALLBACK_PROXY_ADDRESS="0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6"
      ;;
    1301)
      # Unichain Sepolia callback proxy.
      CALLBACK_PROXY_ADDRESS="0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4"
      ;;
  esac
fi

required=(SEPOLIA_RPC_URL SEPOLIA_PRIVATE_KEY POOL_MANAGER CALLBACK_PROXY_ADDRESS EXPECTED_REACT_VM_ID)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "error: missing required env var $key" >&2
    exit 1
  fi
done

export POOL_MANAGER
export CALLBACK_PROXY_ADDRESS
export EXPECTED_REACT_VM_ID
if [[ -n "${COLLATERAL_TOKEN:-}" ]]; then
  export COLLATERAL_TOKEN
else
  unset COLLATERAL_TOKEN || true
fi

cd contracts
forge script script/deploy/DeploySepolia.s.sol:DeploySepoliaScript \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$SEPOLIA_PRIVATE_KEY" \
  --non-interactive \
  --broadcast
