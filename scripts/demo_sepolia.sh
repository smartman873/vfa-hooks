#!/usr/bin/env bash
set -euo pipefail

USE_EXISTING_DEPLOYMENTS="${USE_EXISTING_DEPLOYMENTS:-1}" \
./scripts/demo_testnet_live.sh
