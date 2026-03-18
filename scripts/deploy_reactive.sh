#!/usr/bin/env bash
set -euo pipefail

required=(REACTIVE_RPC_URL REACTIVE_PRIVATE_KEY ORIGIN_CHAIN_ID DESTINATION_CHAIN_ID ORIGIN_HOOK_ADDRESS ORIGIN_MARKET_ADDRESS SETTLEMENT_EXECUTOR_ADDRESS)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "error: missing required env var $key" >&2
    exit 1
  fi
done

cd reactive

REACTIVE_DEPLOY_VALUE_WEI="${REACTIVE_DEPLOY_VALUE_WEI:-100000000000000000}"
CALLBACK_GAS_LIMIT="${CALLBACK_GAS_LIMIT:-1200000}"
VOLUME_SCALE="${VOLUME_SCALE:-10000000000000000000000}"
SPIKE_SCALE="${SPIKE_SCALE:-100000000000000000000}"
MAX_VOLUME_BOOST="${MAX_VOLUME_BOOST:-1000000000000000000}"
MAX_SPIKE_BOOST="${MAX_SPIKE_BOOST:-1000000000000000000}"

CREATE_OUTPUT="$(
  forge create src/VolatilityReactive.sol:VolatilityReactive \
    --rpc-url "$REACTIVE_RPC_URL" \
    --private-key "$REACTIVE_PRIVATE_KEY" \
    --legacy \
    --broadcast \
    --value "$REACTIVE_DEPLOY_VALUE_WEI" \
    --constructor-args \
      "$ORIGIN_CHAIN_ID" \
      "$DESTINATION_CHAIN_ID" \
      "$ORIGIN_HOOK_ADDRESS" \
      "$ORIGIN_MARKET_ADDRESS" \
      "$SETTLEMENT_EXECUTOR_ADDRESS" \
      "$CALLBACK_GAS_LIMIT" \
      "($VOLUME_SCALE,$SPIKE_SCALE,$MAX_VOLUME_BOOST,$MAX_SPIKE_BOOST)"
)"

echo "$CREATE_OUTPUT"

REACTIVE_ADDR="$(printf '%s\n' "$CREATE_OUTPUT" | sed -n 's/^Deployed to: //p')"
DEPLOY_TX_HASH="$(printf '%s\n' "$CREATE_OUTPUT" | sed -n 's/^Transaction hash: //p')"

if [[ -z "$REACTIVE_ADDR" ]] || [[ -z "$DEPLOY_TX_HASH" ]]; then
  echo "error: failed to parse reactive deployment output" >&2
  exit 1
fi

INIT_TX_HASH=""
IS_INITIALIZED="$(cast call "$REACTIVE_ADDR" "subscriptionsInitialized()(bool)" --rpc-url "$REACTIVE_RPC_URL" | tr -d '[:space:]')"
if [[ "$IS_INITIALIZED" != "true" ]]; then
  INIT_OUTPUT="$(
    cast send "$REACTIVE_ADDR" "initializeSubscriptions()" \
      --rpc-url "$REACTIVE_RPC_URL" \
      --private-key "$REACTIVE_PRIVATE_KEY" \
      --legacy
  )"

  echo "$INIT_OUTPUT"

  INIT_TX_HASH="$(printf '%s\n' "$INIT_OUTPUT" | sed -n 's/^transactionHash[[:space:]]*//p')"
  if [[ -z "$INIT_TX_HASH" ]]; then
    echo "error: failed to parse initializeSubscriptions tx hash" >&2
    exit 1
  fi
fi

echo "volatilityReactive $REACTIVE_ADDR"
echo "reactiveDeployTx $DEPLOY_TX_HASH"
echo "reactiveInitTx $INIT_TX_HASH"
