#!/usr/bin/env bash
set -euo pipefail

cd contracts
forge test --match-path test/integration/LifecycleE2E.t.sol -vv
forge test --match-path test/integration/VolatilityHookIntegration.t.sol -vv
