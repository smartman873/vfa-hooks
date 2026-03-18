#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
}

need_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: missing required env var $name" >&2
    exit 1
  fi
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_phase() {
  local msg="$1"
  echo
  echo "[$(now_utc)] === $msg ==="
}

log_step() {
  local msg="$1"
  echo "[$(now_utc)] $msg"
}

chain_name_from_id() {
  case "$1" in
    1301) echo "Unichain Sepolia" ;;
    84532) echo "Base Sepolia" ;;
    11155111) echo "Ethereum Sepolia" ;;
    5318007) echo "Reactive Lasna" ;;
    *) echo "Chain $1" ;;
  esac
}

tx_from_cast_output() {
  local output="$1"
  printf '%s\n' "$output" | sed -n 's/^transactionHash[[:space:]]*//p' | tail -n 1
}

send_sepolia_tx() {
  local to="$1"
  local sig="$2"
  shift 2

  local out=""
  local tx=""
  local status=1
  local attempt=1
  local max_attempts=3

  while ((attempt <= max_attempts)); do
    set +e
    out="$(
      cast send "$to" "$sig" "$@" \
        --rpc-url "$SEPOLIA_RPC_URL" \
        --private-key "$SEPOLIA_PRIVATE_KEY" \
        --gas-price "$DEMO_GAS_PRICE" 2>&1
    )"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
      tx="$(tx_from_cast_output "$out")"
      if [[ -n "$tx" ]]; then
        printf '%s\n' "$tx"
        return 0
      fi
      echo "error: could not parse tx hash for $sig" >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi

    if printf '%s' "$out" | grep -qi "nonce too low"; then
      sleep 2
      attempt=$((attempt + 1))
      continue
    fi

    echo "error: failed tx for $sig" >&2
    printf '%s\n' "$out" >&2
    exit 1
  done

  echo "error: failed tx for $sig after ${max_attempts} attempts" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

env_upsert() {
  local key="$1"
  local value="$2"
  local env_file=".env"

  if [[ ! -f "$env_file" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
    return
  fi

  if rg -n "^${key}=" "$env_file" >/dev/null 2>&1; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$env_file"
    rm -f "${env_file}.bak"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

print_url_list() {
  local title="$1"
  local base="$2"
  local list="$3"
  local count=0

  echo "$title"
  while IFS= read -r tx; do
    [[ -n "$tx" ]] || continue
    count=$((count + 1))
    echo "${base}${tx}"
  done <<< "$list"

  if [[ "$count" -eq 0 ]]; then
    echo "(none)"
  fi
  echo
}

print_md_tx_list() {
  local base="$1"
  local list="$2"
  local count=0

  while IFS= read -r tx; do
    [[ -n "$tx" ]] || continue
    count=$((count + 1))
    echo "- [\`$tx\`](${base}${tx})"
  done <<< "$list"

  if [[ "$count" -eq 0 ]]; then
    echo "- _none_"
  fi
}

print_action_tx() {
  local action="$1"
  local tx="$2"
  local explorer_base="$3"
  if [[ -n "$tx" ]]; then
    log_step "$action tx=$tx"
    log_step "$action url=${explorer_base}${tx}"
  fi
}

load_existing_deployments() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  HOOK_ADDR="$(jq -r '.addresses.originChain.hook // .addresses.baseSepolia.hook // empty' "$file")"
  SHARE_ADDR="$(jq -r '.addresses.originChain.share // .addresses.baseSepolia.share // empty' "$file")"
  MARKET_ADDR="$(jq -r '.addresses.originChain.market // .addresses.baseSepolia.market // empty' "$file")"
  EXECUTOR_ADDR="$(jq -r '.addresses.originChain.executor // .addresses.baseSepolia.executor // empty' "$file")"
  COLLATERAL_ADDR="$(jq -r '.addresses.originChain.collateral // .addresses.baseSepolia.collateral // empty' "$file")"
  REACTIVE_ADDR="$(jq -r '.addresses.reactiveLasna.volatilityReactive // empty' "$file")"

  REACTIVE_DEPLOY_TX="$(jq -r '.transactions.reactiveDeploy // empty' "$file")"
  REACTIVE_INIT_TX="$(jq -r '.transactions.reactiveInit // empty' "$file")"
  SEPOLIA_DEPLOY_TXS="$(jq -r '.transactions.sepoliaDeploy[]? // empty' "$file")"

  if [[ -z "$HOOK_ADDR" || -z "$SHARE_ADDR" || -z "$MARKET_ADDR" || -z "$EXECUTOR_ADDR" || -z "$COLLATERAL_ADDR" || -z "$REACTIVE_ADDR" ]]; then
    return 1
  fi

  return 0
}

load_env_deployments() {
  HOOK_ADDR="${HOOK_ADDR:-${HOOK_ADDRESS:-}}"
  SHARE_ADDR="${SHARE_ADDR:-${SHARE_ADDRESS:-}}"
  MARKET_ADDR="${MARKET_ADDR:-${MARKET_ADDRESS:-}}"
  EXECUTOR_ADDR="${EXECUTOR_ADDR:-${EXECUTOR_ADDRESS:-}}"
  COLLATERAL_ADDR="${COLLATERAL_ADDR:-${COLLATERAL_ADDRESS:-}}"
  REACTIVE_ADDR="${REACTIVE_ADDR:-${VOLATILITY_REACTIVE_ADDRESS:-}}"

  if [[ -n "$HOOK_ADDR" && -n "$SHARE_ADDR" && -n "$MARKET_ADDR" && -n "$EXECUTOR_ADDR" && -n "$COLLATERAL_ADDR" && -n "$REACTIVE_ADDR" ]]; then
    return 0
  fi
  return 1
}

persist_deployments_to_env() {
  env_upsert "HOOK_ADDRESS" "$HOOK_ADDR"
  env_upsert "SHARE_ADDRESS" "$SHARE_ADDR"
  env_upsert "MARKET_ADDRESS" "$MARKET_ADDR"
  env_upsert "EXECUTOR_ADDRESS" "$EXECUTOR_ADDR"
  env_upsert "COLLATERAL_ADDRESS" "$COLLATERAL_ADDR"
  env_upsert "VOLATILITY_REACTIVE_ADDRESS" "$REACTIVE_ADDR"
  if [[ -n "$TELEMETRY_POOL_ID" ]]; then
    env_upsert "TELEMETRY_POOL_ID" "$TELEMETRY_POOL_ID"
  fi
  if [[ -n "$TELEMETRY_TOKEN0_ADDR" ]]; then
    env_upsert "TELEMETRY_TOKEN0_ADDRESS" "$TELEMETRY_TOKEN0_ADDR"
  fi
  if [[ -n "$TELEMETRY_TOKEN1_ADDR" ]]; then
    env_upsert "TELEMETRY_TOKEN1_ADDRESS" "$TELEMETRY_TOKEN1_ADDR"
  fi
  if [[ -n "$HOOKMATE_SWAP_ROUTER_ADDRESS" ]]; then
    env_upsert "HOOKMATE_SWAP_ROUTER_ADDRESS" "$HOOKMATE_SWAP_ROUTER_ADDRESS"
  fi
}

write_deployment_docs() {
  local updated_at="$1"
  local sepolia_deploy_json
  local lifecycle_json
  local telemetry_setup_json
  local telemetry_swap_json

  sepolia_deploy_json="$(
    printf '%s\n' "$SEPOLIA_DEPLOY_TXS" | sed '/^$/d' | jq -R . | jq -s .
  )"
  lifecycle_json="$(
    printf '%s\n' "$LIFECYCLE_TXS" | sed '/^$/d' | jq -R . | jq -s .
  )"
  telemetry_setup_json="$(
    printf '%s\n' "$TELEMETRY_SETUP_TXS" | sed '/^$/d' | jq -R . | jq -s .
  )"
  telemetry_swap_json="$(
    printf '%s\n' "$TELEMETRY_SWAP_TXS" | sed '/^$/d' | jq -R . | jq -s .
  )"

  jq -n \
    --arg updatedAt "$updated_at" \
    --arg originChainName "$ORIGIN_CHAIN_NAME" \
    --arg sepoliaChainId "$SEPOLIA_CHAIN_ID" \
    --arg reactiveChainId "$REACTIVE_CHAIN_ID" \
    --arg poolManager "$POOL_MANAGER_ADDRESS" \
    --arg callbackProxy "$BASE_CALLBACK_PROXY" \
    --arg hook "$HOOK_ADDR" \
    --arg share "$SHARE_ADDR" \
    --arg market "$MARKET_ADDR" \
    --arg executor "$EXECUTOR_ADDR" \
    --arg collateral "$COLLATERAL_ADDR" \
    --arg hookmateSwapRouter "$HOOKMATE_SWAP_ROUTER_ADDRESS" \
    --arg telemetryPoolId "$TELEMETRY_POOL_ID" \
    --arg telemetryToken0 "$TELEMETRY_TOKEN0_ADDR" \
    --arg telemetryToken1 "$TELEMETRY_TOKEN1_ADDR" \
    --arg systemContract "$SYSTEM_CONTRACT_ADDR" \
    --arg volatilityReactive "$REACTIVE_ADDR" \
    --arg reactiveDeploy "$REACTIVE_DEPLOY_TX" \
    --arg reactiveInit "$REACTIVE_INIT_TX" \
    --argjson sepoliaDeploy "$sepolia_deploy_json" \
    --argjson telemetrySetup "$telemetry_setup_json" \
    --argjson telemetrySwap "$telemetry_swap_json" \
    --argjson lifecycle "$lifecycle_json" \
    '{
      updatedAt: $updatedAt,
      addresses: {
        originChain: {
          name: $originChainName,
          chainId: $sepoliaChainId,
          poolManager: $poolManager,
          callbackProxy: $callbackProxy,
          hook: $hook,
          share: $share,
          market: $market,
          executor: $executor,
          collateral: $collateral,
          hookmateSwapRouter: $hookmateSwapRouter,
          telemetryPoolId: $telemetryPoolId,
          telemetryToken0: $telemetryToken0,
          telemetryToken1: $telemetryToken1
        },
        baseSepolia: {
          chainId: $sepoliaChainId,
          poolManager: $poolManager,
          callbackProxy: $callbackProxy,
          hook: $hook,
          share: $share,
          market: $market,
          executor: $executor,
          collateral: $collateral,
          hookmateSwapRouter: $hookmateSwapRouter,
          telemetryPoolId: $telemetryPoolId,
          telemetryToken0: $telemetryToken0,
          telemetryToken1: $telemetryToken1
        },
        reactiveLasna: {
          chainId: $reactiveChainId,
          systemContract: $systemContract,
          volatilityReactive: $volatilityReactive
        }
      },
      transactions: {
        sepoliaDeploy: $sepoliaDeploy,
        telemetrySetup: $telemetrySetup,
        telemetrySwap: $telemetrySwap,
        reactiveDeploy: $reactiveDeploy,
        reactiveInit: $reactiveInit,
        lifecycle: $lifecycle
      }
    }' > "$DEPLOYMENTS_JSON_PATH"

  {
    echo "# Deployed Addresses"
    echo
    echo "_Last updated: ${updated_at}_"
    echo
    echo "## ${ORIGIN_CHAIN_NAME}"
    echo
    echo "- Chain ID: \`$SEPOLIA_CHAIN_ID\`"
    echo "- PoolManager: \`$POOL_MANAGER_ADDRESS\`"
    echo "- Callback Proxy: \`$BASE_CALLBACK_PROXY\`"
    echo "- Hook: \`$HOOK_ADDR\`"
    echo "- Share Token: \`$SHARE_ADDR\`"
    echo "- Market: \`$MARKET_ADDR\`"
    echo "- Settlement Executor: \`$EXECUTOR_ADDR\`"
    echo "- Collateral: \`$COLLATERAL_ADDR\`"
    echo "- Hookmate Swap Router: \`$HOOKMATE_SWAP_ROUTER_ADDRESS\`"
    if [[ -n "$TELEMETRY_POOL_ID" ]]; then
      echo "- Telemetry Pool ID: \`$TELEMETRY_POOL_ID\`"
    fi
    if [[ -n "$TELEMETRY_TOKEN0_ADDR" ]]; then
      echo "- Telemetry Token0: \`$TELEMETRY_TOKEN0_ADDR\`"
    fi
    if [[ -n "$TELEMETRY_TOKEN1_ADDR" ]]; then
      echo "- Telemetry Token1: \`$TELEMETRY_TOKEN1_ADDR\`"
    fi
    echo
    echo "### Deployment Transactions"
    print_md_tx_list "$SEPOLIA_EXPLORER_TX_BASE" "$SEPOLIA_DEPLOY_TXS"
    echo
    echo "### Hook Telemetry Setup Transactions"
    print_md_tx_list "$SEPOLIA_EXPLORER_TX_BASE" "$TELEMETRY_SETUP_TXS"
    echo
    echo "### Post-Epoch Telemetry Swap Transactions"
    print_md_tx_list "$SEPOLIA_EXPLORER_TX_BASE" "$TELEMETRY_SWAP_TXS"
    echo
    echo "### Last Live E2E Lifecycle Transactions"
    print_md_tx_list "$SEPOLIA_EXPLORER_TX_BASE" "$LIFECYCLE_TXS"
    echo
    echo "## Reactive Lasna"
    echo
    echo "- Chain ID: \`$REACTIVE_CHAIN_ID\`"
    echo "- System Contract: \`$SYSTEM_CONTRACT_ADDR\`"
    echo "- VolatilityReactive: \`$REACTIVE_ADDR\`"
    echo
    echo "### Deployment Transactions"
    if [[ -n "$REACTIVE_DEPLOY_TX" ]]; then
      echo "- [\`$REACTIVE_DEPLOY_TX\`](${REACTIVE_EXPLORER_TX_BASE}${REACTIVE_DEPLOY_TX})"
    else
      echo "- _none_"
    fi
    if [[ -n "$REACTIVE_INIT_TX" ]]; then
      echo "- [\`$REACTIVE_INIT_TX\`](${REACTIVE_EXPLORER_TX_BASE}${REACTIVE_INIT_TX})"
    else
      echo "- _none_"
    fi
  } > "$DEPLOYMENTS_MD_PATH"
}

need_cmd forge
need_cmd cast
need_cmd jq
need_cmd awk
need_cmd sed

need_env SEPOLIA_RPC_URL
need_env SEPOLIA_PRIVATE_KEY
need_env REACTIVE_RPC_URL
need_env REACTIVE_PRIVATE_KEY
need_env ORIGIN_CHAIN_ID
need_env DESTINATION_CHAIN_ID
need_env POOL_MANAGER_ADDRESS

SEPOLIA_CHAIN_ID="${SEPOLIA_CHAIN_ID:-84532}"
REACTIVE_CHAIN_ID="${REACTIVE_CHAIN_ID:-5318007}"
SYSTEM_CONTRACT_ADDR="${SYSTEM_CONTRACT_ADDR:-0x0000000000000000000000000000000000fffFfF}"
if [[ -z "${SEPOLIA_EXPLORER_TX_BASE:-}" ]]; then
  case "$SEPOLIA_CHAIN_ID" in
    1301) SEPOLIA_EXPLORER_TX_BASE="https://sepolia.uniscan.xyz/tx/" ;;
    11155111) SEPOLIA_EXPLORER_TX_BASE="https://sepolia.etherscan.io/tx/" ;;
    *) SEPOLIA_EXPLORER_TX_BASE="https://sepolia.basescan.org/tx/" ;;
  esac
fi
REACTIVE_EXPLORER_TX_BASE="${REACTIVE_EXPLORER_TX_BASE:-https://lasna.reactscan.net/tx/}"
DEPLOYMENTS_JSON_PATH="${DEPLOYMENTS_JSON_PATH:-docs/deployments.testnet.json}"
DEPLOYMENTS_MD_PATH="${DEPLOYMENTS_MD_PATH:-docs/deployed-addresses.md}"
USE_EXISTING_DEPLOYMENTS="${USE_EXISTING_DEPLOYMENTS:-1}"
FORCE_REDEPLOY="${FORCE_REDEPLOY:-0}"
ORIGIN_CHAIN_NAME="$(chain_name_from_id "$SEPOLIA_CHAIN_ID")"
REACTIVE_CHAIN_NAME="$(chain_name_from_id "$REACTIVE_CHAIN_ID")"

DEMO_EPOCH_DURATION_SECONDS="${DEMO_EPOCH_DURATION_SECONDS:-120}"
DEMO_MIN_TRADE_SIZE="${DEMO_MIN_TRADE_SIZE:-1000000}"
DEMO_MAX_TRADE_SIZE="${DEMO_MAX_TRADE_SIZE:-1000000000000000000000}"
DEMO_BASELINE_VOLATILITY="${DEMO_BASELINE_VOLATILITY:-100000000000000000000}"
DEMO_REALIZED_VOLATILITY="${DEMO_REALIZED_VOLATILITY:-150000000000000000000}"
DEMO_LONG_AMOUNT="${DEMO_LONG_AMOUNT:-10000000000000000000}"
DEMO_SHORT_AMOUNT="${DEMO_SHORT_AMOUNT:-8000000000000000000}"
DEMO_APPROVAL_AMOUNT="${DEMO_APPROVAL_AMOUNT:-1000000000000000000000000}"
DEMO_POOL_SALT="${DEMO_POOL_SALT:-VFA/LIVE-DEMO}"
DEMO_GAS_PRICE="${DEMO_GAS_PRICE:-5gwei}"
SETTLEMENT_MODE="${SETTLEMENT_MODE:-reactive}"
SETTLEMENT_TIMEOUT_SECONDS="${SETTLEMENT_TIMEOUT_SECONDS:-300}"
SETTLEMENT_POLL_INTERVAL_SECONDS="${SETTLEMENT_POLL_INTERVAL_SECONDS:-6}"
ALLOW_MANUAL_FALLBACK="${ALLOW_MANUAL_FALLBACK:-0}"
ENABLE_HOOK_TELEMETRY="${ENABLE_HOOK_TELEMETRY:-1}"
TRIGGER_POST_EPOCH_TELEMETRY_SWAP="${TRIGGER_POST_EPOCH_TELEMETRY_SWAP:-1}"

HOOKMATE_SWAP_ROUTER_ADDRESS="${HOOKMATE_SWAP_ROUTER_ADDRESS:-}"
if [[ -z "$HOOKMATE_SWAP_ROUTER_ADDRESS" ]]; then
  case "$SEPOLIA_CHAIN_ID" in
    1301) HOOKMATE_SWAP_ROUTER_ADDRESS="0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba" ;;
    11155111) HOOKMATE_SWAP_ROUTER_ADDRESS="0xf13D190e9117920c703d79B5F33732e10049b115" ;;
    84532) HOOKMATE_SWAP_ROUTER_ADDRESS="0x71cD4Ea054F9Cb3D3BF6251A00673303411A7DD9" ;;
    421614) HOOKMATE_SWAP_ROUTER_ADDRESS="0xcD8D7e10A7aA794C389d56A07d85d63E28780220" ;;
  esac
fi

BASE_CALLBACK_PROXY="${CALLBACK_PROXY_ADDRESS:-${DESTINATION_CALLBACK_PROXY_ADDR:-}}"
if [[ -z "$BASE_CALLBACK_PROXY" ]]; then
  case "$SEPOLIA_CHAIN_ID" in
    84532) BASE_CALLBACK_PROXY="0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6" ;;
    1301) BASE_CALLBACK_PROXY="0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4" ;;
    11155111) BASE_CALLBACK_PROXY="0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA" ;;
  esac
fi
need_env BASE_CALLBACK_PROXY
if [[ "$ENABLE_HOOK_TELEMETRY" == "1" ]]; then
  need_env POSITION_MANAGER_ADDRESS
  need_env HOOKMATE_SWAP_ROUTER_ADDRESS
fi

case "${SEPOLIA_CHAIN_ID:-}" in
  84532|11155111|5318007|421614|1301|43113|80002|97)
    case "${DESTINATION_CHAIN_ID:-}" in
      84532|11155111|5318007|421614|1301|43113|80002|97) ;;
      *)
        echo "error: DESTINATION_CHAIN_ID=$DESTINATION_CHAIN_ID appears to be non-testnet while origin is testnet chain $SEPOLIA_CHAIN_ID" >&2
        exit 1
        ;;
    esac
    ;;
esac

SEPOLIA_LOG="$(mktemp)"
REACTIVE_LOG="$(mktemp)"
TELEMETRY_SETUP_LOG="$(mktemp)"
TELEMETRY_SWAP_LOG="$(mktemp)"
cleanup() {
  rm -f "$SEPOLIA_LOG" "$REACTIVE_LOG" "$TELEMETRY_SETUP_LOG" "$TELEMETRY_SWAP_LOG"
}
trap cleanup EXIT

HOOK_ADDR=""
SHARE_ADDR=""
MARKET_ADDR=""
EXECUTOR_ADDR=""
COLLATERAL_ADDR=""
REACTIVE_ADDR=""
TELEMETRY_POOL_ID="${TELEMETRY_POOL_ID:-}"
TELEMETRY_TOKEN0_ADDR="${TELEMETRY_TOKEN0_ADDRESS:-}"
TELEMETRY_TOKEN1_ADDR="${TELEMETRY_TOKEN1_ADDRESS:-}"
REACTIVE_DEPLOY_TX=""
REACTIVE_INIT_TX=""
SEPOLIA_DEPLOY_TXS=""
TELEMETRY_SETUP_TXS=""
TELEMETRY_SWAP_TXS=""

USED_EXISTING="0"
if [[ "$USE_EXISTING_DEPLOYMENTS" == "1" && "$FORCE_REDEPLOY" != "1" ]]; then
  if load_env_deployments; then
    USED_EXISTING="1"
    log_step "Using existing deployment addresses from .env"
  elif load_existing_deployments "$DEPLOYMENTS_JSON_PATH"; then
    USED_EXISTING="1"
    log_step "Using existing deployment addresses from $DEPLOYMENTS_JSON_PATH"
  fi
fi

if [[ "$USED_EXISTING" == "1" ]]; then
  log_phase "Phase 1/6 - Reuse Existing Deployments"
  log_step "Origin chain: ${ORIGIN_CHAIN_NAME} (${SEPOLIA_CHAIN_ID})"
  log_step "Reactive chain: ${REACTIVE_CHAIN_NAME} (${REACTIVE_CHAIN_ID})"
else
  log_phase "Phase 1/6 - Deploy Origin Contracts"
  log_step "Deploying market/hook/executor stack on ${ORIGIN_CHAIN_NAME} (${SEPOLIA_CHAIN_ID})"
  POOL_MANAGER="$POOL_MANAGER_ADDRESS" ./scripts/deploy_sepolia.sh 2>&1 | tee "$SEPOLIA_LOG"

  HOOK_ADDR="$(awk '/^[[:space:]]*hook /{print $2}' "$SEPOLIA_LOG" | tail -n 1)"
  SHARE_ADDR="$(awk '/^[[:space:]]*share /{print $2}' "$SEPOLIA_LOG" | tail -n 1)"
  MARKET_ADDR="$(awk '/^[[:space:]]*market /{print $2}' "$SEPOLIA_LOG" | tail -n 1)"
  EXECUTOR_ADDR="$(awk '/^[[:space:]]*executor /{print $2}' "$SEPOLIA_LOG" | tail -n 1)"
  COLLATERAL_ADDR="$(awk '/^[[:space:]]*collateral /{print $2}' "$SEPOLIA_LOG" | tail -n 1)"

  if [[ -z "$HOOK_ADDR" || -z "$SHARE_ADDR" || -z "$MARKET_ADDR" || -z "$EXECUTOR_ADDR" || -z "$COLLATERAL_ADDR" ]]; then
    echo "error: failed to parse deploy_sepolia output addresses" >&2
    exit 1
  fi

  SEPOLIA_BROADCAST="contracts/broadcast/DeploySepolia.s.sol/${SEPOLIA_CHAIN_ID}/run-latest.json"
  if [[ ! -f "$SEPOLIA_BROADCAST" ]]; then
    echo "error: missing broadcast file: $SEPOLIA_BROADCAST" >&2
    exit 1
  fi

  SEPOLIA_DEPLOY_TXS="$(
    jq -r '.transactions[].hash' "$SEPOLIA_BROADCAST" | awk '!seen[$0]++'
  )"
  if [[ -n "$SEPOLIA_DEPLOY_TXS" ]]; then
    log_step "Origin deployment transactions captured from Foundry broadcast JSON"
  fi

  log_phase "Phase 2/6 - Deploy Reactive Contract"
  log_step "Deploying VolatilityReactive on ${REACTIVE_CHAIN_NAME} (${REACTIVE_CHAIN_ID}) and initializing subscriptions"
  export ORIGIN_HOOK_ADDRESS="$HOOK_ADDR"
  export ORIGIN_MARKET_ADDRESS="$MARKET_ADDR"
  export SETTLEMENT_EXECUTOR_ADDRESS="$EXECUTOR_ADDR"
  ./scripts/deploy_reactive.sh 2>&1 | tee "$REACTIVE_LOG"

  REACTIVE_ADDR="$(awk '/^volatilityReactive /{print $2}' "$REACTIVE_LOG" | tail -n 1)"
  REACTIVE_DEPLOY_TX="$(awk '/^reactiveDeployTx /{print $2}' "$REACTIVE_LOG" | tail -n 1)"
  REACTIVE_INIT_TX="$(awk '/^reactiveInitTx /{print $2}' "$REACTIVE_LOG" | tail -n 1)"

  if [[ -z "$REACTIVE_ADDR" ]]; then
    echo "error: failed to parse deploy_reactive output" >&2
    exit 1
  fi
  print_action_tx "reactive-deploy" "$REACTIVE_DEPLOY_TX" "$REACTIVE_EXPLORER_TX_BASE"
  print_action_tx "reactive-initialize-subscriptions" "$REACTIVE_INIT_TX" "$REACTIVE_EXPLORER_TX_BASE"
fi

if [[ "$USED_EXISTING" == "1" ]]; then
  log_phase "Phase 2/6 - Reuse Reactive Deployment"
  log_step "Reactive deployment address reused for callback lifecycle checks"
fi

persist_deployments_to_env

if [[ "$ENABLE_HOOK_TELEMETRY" == "1" ]]; then
  log_phase "Phase 3/7 - Setup Hooked Uniswap v4 Pool"
  log_step "Deploying telemetry tokens, initializing hooked pool, and seeding liquidity"

  (
    cd contracts
    HOOK_ADDRESS="$HOOK_ADDR" \
      POOL_MANAGER_ADDRESS="$POOL_MANAGER_ADDRESS" \
      POSITION_MANAGER_ADDRESS="$POSITION_MANAGER_ADDRESS" \
      DEMO_HOOK_TOKEN_SUFFIX="$(date +%s)" \
      forge script script/demo/SetupHookedPool.s.sol:SetupHookedPoolScript \
        --rpc-url "$SEPOLIA_RPC_URL" \
        --private-key "$SEPOLIA_PRIVATE_KEY" \
        --legacy \
        --with-gas-price "$DEMO_GAS_PRICE" \
        --slow \
        --broadcast \
        --non-interactive
  ) 2>&1 | tee "$TELEMETRY_SETUP_LOG"

  TELEMETRY_TOKEN0_ADDR="$(awk '/^[[:space:]]*telemetryToken0 /{print $2}' "$TELEMETRY_SETUP_LOG" | tail -n 1)"
  TELEMETRY_TOKEN1_ADDR="$(awk '/^[[:space:]]*telemetryToken1 /{print $2}' "$TELEMETRY_SETUP_LOG" | tail -n 1)"
  TELEMETRY_POOL_ID="$(
    awk '
      /^[[:space:]]*telemetryPoolId[[:space:]]*$/ {capture=1; next}
      capture && $1 ~ /^0x[0-9a-fA-F]{64}$/ {print $1; exit}
    ' "$TELEMETRY_SETUP_LOG"
  )"

  if [[ -z "$TELEMETRY_TOKEN0_ADDR" || -z "$TELEMETRY_TOKEN1_ADDR" || -z "$TELEMETRY_POOL_ID" ]]; then
    echo "error: failed to parse hooked pool setup outputs" >&2
    exit 1
  fi

  SETUP_BROADCAST="contracts/broadcast/SetupHookedPool.s.sol/${SEPOLIA_CHAIN_ID}/run-latest.json"
  if [[ -f "$SETUP_BROADCAST" ]]; then
    TELEMETRY_SETUP_TXS="$(
      jq -r '.transactions[].hash' "$SETUP_BROADCAST" | awk '!seen[$0]++'
    )"
  fi

  DEMO_POOL_ID="$TELEMETRY_POOL_ID"
  log_step "telemetryPoolId=$TELEMETRY_POOL_ID"
  log_step "telemetryToken0=$TELEMETRY_TOKEN0_ADDR"
  log_step "telemetryToken1=$TELEMETRY_TOKEN1_ADDR"
else
  DEMO_POOL_ID="$(cast keccak "${DEMO_POOL_SALT}/$(date +%s)")"
fi

persist_deployments_to_env

log_phase "Phase 4/7 - User Journey: Open Volatility Positions"
log_step "User approves collateral, market owner creates an epoch pool, user opens LONG and SHORT positions"
log_step "demoPoolId=$DEMO_POOL_ID"
log_step "settlementMode=$SETTLEMENT_MODE"

PREV_NEXT_POSITION_ID_HEX="$(
  cast call "$MARKET_ADDR" "nextPositionId()(uint256)" --rpc-url "$SEPOLIA_RPC_URL"
)"
PREV_NEXT_POSITION_ID="$(cast to-dec "$PREV_NEXT_POSITION_ID_HEX")"
LONG_POSITION_ID="$((PREV_NEXT_POSITION_ID + 1))"
SHORT_POSITION_ID="$((PREV_NEXT_POSITION_ID + 2))"

TX_APPROVE="$(
  send_sepolia_tx \
    "$COLLATERAL_ADDR" \
    "approve(address,uint256)" \
    "$MARKET_ADDR" \
    "$DEMO_APPROVAL_AMOUNT"
)"
print_action_tx "approve-collateral" "$TX_APPROVE" "$SEPOLIA_EXPLORER_TX_BASE"
TX_CREATE_POOL="$(
  send_sepolia_tx \
    "$MARKET_ADDR" \
    "createVolatilityPool(bytes32,uint64,uint256,uint256,uint256)" \
    "$DEMO_POOL_ID" \
    "$DEMO_EPOCH_DURATION_SECONDS" \
    "$DEMO_MIN_TRADE_SIZE" \
    "$DEMO_MAX_TRADE_SIZE" \
    "$DEMO_BASELINE_VOLATILITY"
)"
print_action_tx "create-volatility-pool" "$TX_CREATE_POOL" "$SEPOLIA_EXPLORER_TX_BASE"
TX_OPEN_LONG="$(
  send_sepolia_tx \
    "$MARKET_ADDR" \
    "openPosition(bytes32,bool,uint256)" \
    "$DEMO_POOL_ID" \
    true \
    "$DEMO_LONG_AMOUNT"
)"
print_action_tx "open-long-position" "$TX_OPEN_LONG" "$SEPOLIA_EXPLORER_TX_BASE"
TX_OPEN_SHORT="$(
  send_sepolia_tx \
    "$MARKET_ADDR" \
    "openPosition(bytes32,bool,uint256)" \
    "$DEMO_POOL_ID" \
    false \
    "$DEMO_SHORT_AMOUNT"
)"
print_action_tx "open-short-position" "$TX_OPEN_SHORT" "$SEPOLIA_EXPLORER_TX_BASE"

EPOCH_VIEW="$(
  cast call \
    "$MARKET_ADDR" \
    "epochs(bytes32,uint256)(uint64,uint64,uint256,uint256,uint256,uint256,bool)" \
    "$DEMO_POOL_ID" \
    1 \
    --rpc-url "$SEPOLIA_RPC_URL"
)"
EPOCH_END_TS="$(printf '%s\n' "$EPOCH_VIEW" | sed -n '2p' | awk '{print $1}')"
NOW_TS="$(date +%s)"
WAIT_SECONDS="$((EPOCH_END_TS - NOW_TS + 8))"
if ((WAIT_SECONDS > 0)); then
  log_phase "Phase 5/7 - Epoch Wait"
  log_step "Waiting ${WAIT_SECONDS}s for epoch end before settlement"
  sleep "$WAIT_SECONDS"
fi

REPLAY_KEY="$(cast keccak "VFA/LIVE-DEMO/REPLAY/$(date +%s)")"
TX_SETTLE_MANUAL=""
if [[ "$SETTLEMENT_MODE" == "manual" ]]; then
  log_phase "Phase 6/7 - Settlement (Manual)"
  log_step "Executing owner-only manual settlement path on SettlementExecutor"
  TX_SETTLE_MANUAL="$(
    send_sepolia_tx \
      "$EXECUTOR_ADDR" \
      "settleEpochManual(bytes32,uint256,uint256,uint256,bytes32)" \
      "$DEMO_POOL_ID" \
      1 \
      "$DEMO_REALIZED_VOLATILITY" \
      "$DEMO_BASELINE_VOLATILITY" \
      "$REPLAY_KEY"
  )"
  print_action_tx "manual-settlement" "$TX_SETTLE_MANUAL" "$SEPOLIA_EXPLORER_TX_BASE"
elif [[ "$SETTLEMENT_MODE" == "reactive" ]]; then
  log_phase "Phase 6/7 - Settlement (Reactive Callback)"
  log_step "Waiting for Reactive callback to settle epoch on destination chain"
  if [[ "$ENABLE_HOOK_TELEMETRY" == "1" && "$TRIGGER_POST_EPOCH_TELEMETRY_SWAP" == "1" ]]; then
    log_step "Triggering post-epoch hooked swap to emit TelemetryUpdated for callback settlement"
    DEMO_TELEMETRY_SWAP_AMOUNT_IN="${DEMO_TELEMETRY_SWAP_AMOUNT_IN:-1000000000000000000}"
    DEMO_HOOK_FEE="${DEMO_HOOK_FEE:-3000}"
    DEMO_HOOK_TICK_SPACING="${DEMO_HOOK_TICK_SPACING:-60}"
    DEMO_TELEMETRY_DEADLINE_SECONDS="${DEMO_TELEMETRY_DEADLINE_SECONDS:-900}"
    DEMO_TELEMETRY_RECIPIENT="${DEMO_TELEMETRY_RECIPIENT:-$OWNER_ADDRESS}"
    if [[ -z "$DEMO_TELEMETRY_RECIPIENT" ]]; then
      DEMO_TELEMETRY_RECIPIENT="$(cast wallet address --private-key "$SEPOLIA_PRIVATE_KEY")"
    fi
    DEMO_SWAP_DEADLINE="$(( $(date +%s) + DEMO_TELEMETRY_DEADLINE_SECONDS ))"

    TX_APPROVE_ROUTER="$(
      send_sepolia_tx \
        "$TELEMETRY_TOKEN0_ADDR" \
        "approve(address,uint256)" \
        "$HOOKMATE_SWAP_ROUTER_ADDRESS" \
        "$DEMO_APPROVAL_AMOUNT"
    )"
    print_action_tx "approve-telemetry-token-for-router" "$TX_APPROVE_ROUTER" "$SEPOLIA_EXPLORER_TX_BASE"

    TX_TELEMETRY_SWAP="$(
      send_sepolia_tx \
        "$HOOKMATE_SWAP_ROUTER_ADDRESS" \
        "swapExactTokensForTokens(uint256,uint256,bool,(address,address,uint24,int24,address),bytes,address,uint256)" \
        "$DEMO_TELEMETRY_SWAP_AMOUNT_IN" \
        0 \
        true \
        "($TELEMETRY_TOKEN0_ADDR,$TELEMETRY_TOKEN1_ADDR,$DEMO_HOOK_FEE,$DEMO_HOOK_TICK_SPACING,$HOOK_ADDR)" \
        0x \
        "$DEMO_TELEMETRY_RECIPIENT" \
        "$DEMO_SWAP_DEADLINE"
    )"
    print_action_tx "post-epoch-telemetry-swap" "$TX_TELEMETRY_SWAP" "$SEPOLIA_EXPLORER_TX_BASE"

    TELEMETRY_SWAP_TXS="$(
      printf '%s\n' "$TX_APPROVE_ROUTER" "$TX_TELEMETRY_SWAP"
    )"
    print_url_list "${ORIGIN_CHAIN_NAME} post-epoch telemetry swap tx URLs:" "$SEPOLIA_EXPLORER_TX_BASE" "$TELEMETRY_SWAP_TXS"
  fi
  START_WAIT="$(date +%s)"
  while true; do
    IS_SETTLED="$(
      cast call "$MARKET_ADDR" "isEpochSettled(bytes32,uint256)(bool)" "$DEMO_POOL_ID" 1 --rpc-url "$SEPOLIA_RPC_URL" | tr -d '[:space:]'
    )"
    if [[ "$IS_SETTLED" == "true" ]]; then
      break
    fi

    NOW_WAIT="$(date +%s)"
    if ((NOW_WAIT - START_WAIT >= SETTLEMENT_TIMEOUT_SECONDS)); then
      if [[ "$ALLOW_MANUAL_FALLBACK" == "1" ]]; then
        log_step "Reactive callback timeout reached (no post-epoch TelemetryUpdated observed); executing manual fallback settlement"
        TX_SETTLE_MANUAL="$(
          send_sepolia_tx \
            "$EXECUTOR_ADDR" \
            "settleEpochManual(bytes32,uint256,uint256,uint256,bytes32)" \
            "$DEMO_POOL_ID" \
            1 \
            "$DEMO_REALIZED_VOLATILITY" \
            "$DEMO_BASELINE_VOLATILITY" \
            "$REPLAY_KEY"
        )"
        print_action_tx "manual-fallback-settlement" "$TX_SETTLE_MANUAL" "$SEPOLIA_EXPLORER_TX_BASE"
        break
      fi

      echo "error: epoch was not settled via Reactive callback within ${SETTLEMENT_TIMEOUT_SECONDS}s" >&2
      echo "hint: generate hook telemetry after epoch end, or run with SETTLEMENT_MODE=manual / ALLOW_MANUAL_FALLBACK=1" >&2
      exit 1
    fi

    sleep "$SETTLEMENT_POLL_INTERVAL_SECONDS"
  done
else
  echo "error: unsupported SETTLEMENT_MODE=$SETTLEMENT_MODE (expected: reactive|manual)" >&2
  exit 1
fi
log_phase "Phase 7/7 - User Journey: Claim PnL"
log_step "User claims LONG and SHORT position payouts"
TX_CLAIM_LONG="$(
  send_sepolia_tx \
    "$MARKET_ADDR" \
    "claim(uint256)" \
    "$LONG_POSITION_ID"
)"
print_action_tx "claim-long-position" "$TX_CLAIM_LONG" "$SEPOLIA_EXPLORER_TX_BASE"
TX_CLAIM_SHORT="$(
  send_sepolia_tx \
    "$MARKET_ADDR" \
    "claim(uint256)" \
    "$SHORT_POSITION_ID"
)"
print_action_tx "claim-short-position" "$TX_CLAIM_SHORT" "$SEPOLIA_EXPLORER_TX_BASE"

LIFECYCLE_TXS="$(
  printf '%s\n' \
    "$TELEMETRY_SETUP_TXS" \
    "$TX_APPROVE" \
    "$TX_CREATE_POOL" \
    "$TX_OPEN_LONG" \
    "$TX_OPEN_SHORT" \
    "$TELEMETRY_SWAP_TXS" \
    "$TX_SETTLE_MANUAL" \
    "$TX_CLAIM_LONG" \
    "$TX_CLAIM_SHORT"
)"

UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
write_deployment_docs "$UPDATED_AT"

log_phase "Explorer Outputs"
echo
print_url_list "${ORIGIN_CHAIN_NAME} deployment tx URLs:" "$SEPOLIA_EXPLORER_TX_BASE" "$SEPOLIA_DEPLOY_TXS"
print_url_list "${ORIGIN_CHAIN_NAME} hook telemetry setup tx URLs:" "$SEPOLIA_EXPLORER_TX_BASE" "$TELEMETRY_SETUP_TXS"
print_url_list "${ORIGIN_CHAIN_NAME} post-epoch telemetry swap tx URLs:" "$SEPOLIA_EXPLORER_TX_BASE" "$TELEMETRY_SWAP_TXS"
print_url_list "${ORIGIN_CHAIN_NAME} lifecycle demo tx URLs:" "$SEPOLIA_EXPLORER_TX_BASE" "$LIFECYCLE_TXS"

echo "${REACTIVE_CHAIN_NAME} tx URLs:"
if [[ -n "$REACTIVE_DEPLOY_TX" ]]; then
  echo "${REACTIVE_EXPLORER_TX_BASE}${REACTIVE_DEPLOY_TX}"
fi
if [[ -n "$REACTIVE_INIT_TX" ]]; then
  echo "${REACTIVE_EXPLORER_TX_BASE}${REACTIVE_INIT_TX}"
fi
echo

echo "Deployed addresses (also written to docs and .env):"
echo "hook                $HOOK_ADDR"
echo "share               $SHARE_ADDR"
echo "market              $MARKET_ADDR"
echo "executor            $EXECUTOR_ADDR"
echo "collateral          $COLLATERAL_ADDR"
echo "volatilityReactive  $REACTIVE_ADDR"
if [[ -n "$TELEMETRY_POOL_ID" ]]; then
  echo "telemetryPoolId     $TELEMETRY_POOL_ID"
fi
if [[ -n "$TELEMETRY_TOKEN0_ADDR" ]]; then
  echo "telemetryToken0     $TELEMETRY_TOKEN0_ADDR"
fi
if [[ -n "$TELEMETRY_TOKEN1_ADDR" ]]; then
  echo "telemetryToken1     $TELEMETRY_TOKEN1_ADDR"
fi
echo
echo "Docs updated:"
echo "- $DEPLOYMENTS_JSON_PATH"
echo "- $DEPLOYMENTS_MD_PATH"
