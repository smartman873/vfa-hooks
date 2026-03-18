#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="$ROOT_DIR/deps"
PINSET_ID="3779387"
V4_CORE_SHA="80311e34080fee64b6fc6c916e9a51a437d0e482"
V4_PERIPHERY_SHA="ea2bf2e1ba6863bb809fc2ff791744f308c4a26d"

mkdir -p "$DEPS_DIR"

clone_or_update() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "$target_dir/.git" ]]; then
    git -C "$target_dir" fetch --tags --prune origin
  else
    git clone "$repo_url" "$target_dir"
  fi
}

checkout_exact() {
  local target_dir="$1"
  local sha="$2"

  if ! git -C "$target_dir" rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1; then
    echo "error: commit ${sha} not found in $(basename "$target_dir")" >&2
    exit 1
  fi

  git -C "$target_dir" checkout "$sha" >/dev/null
  local short
  short="$(git -C "$target_dir" rev-parse --short HEAD)"
  if [[ "$short" != "${sha:0:7}"* ]]; then
    echo "error: $(basename "$target_dir") pin mismatch, expected ${sha:0:7}, got ${short}" >&2
    exit 1
  fi
}

clone_or_update "https://github.com/foundry-rs/forge-std.git" "$DEPS_DIR/forge-std"
clone_or_update "https://github.com/Uniswap/v4-core.git" "$DEPS_DIR/v4-core"
clone_or_update "https://github.com/Uniswap/v4-periphery.git" "$DEPS_DIR/v4-periphery"
clone_or_update "https://github.com/Uniswap/permit2.git" "$DEPS_DIR/permit2"
clone_or_update "https://github.com/transmissions11/solmate.git" "$DEPS_DIR/solmate"
clone_or_update "https://github.com/akshatmittal/hookmate.git" "$DEPS_DIR/hookmate"
clone_or_update "https://github.com/OpenZeppelin/openzeppelin-contracts.git" "$DEPS_DIR/openzeppelin-contracts"
clone_or_update "https://github.com/Reactive-Network/reactive-lib.git" "$DEPS_DIR/reactive-lib"

checkout_exact "$DEPS_DIR/v4-core" "$V4_CORE_SHA"
checkout_exact "$DEPS_DIR/v4-periphery" "$V4_PERIPHERY_SHA"

# Keep shared deps deterministic for contracts and reactive projects.
git -C "$DEPS_DIR/permit2" checkout main >/dev/null || true
git -C "$DEPS_DIR/solmate" checkout main >/dev/null || true
git -C "$DEPS_DIR/hookmate" checkout main >/dev/null || true
git -C "$DEPS_DIR/forge-std" checkout master >/dev/null || true
git -C "$DEPS_DIR/openzeppelin-contracts" checkout master >/dev/null || true
git -C "$DEPS_DIR/reactive-lib" checkout main >/dev/null || true

cat > "$DEPS_DIR/uniswap-pinset.json" <<JSON
{
  "pinset_id": "$PINSET_ID",
  "v4_core": "$V4_CORE_SHA",
  "v4_periphery": "$V4_PERIPHERY_SHA"
}
JSON

echo "bootstrap complete"
echo "pinset: ${PINSET_ID}"
echo "pinned: v4-core=$(git -C "$DEPS_DIR/v4-core" rev-parse --short HEAD)"
echo "pinned: v4-periphery=$(git -C "$DEPS_DIR/v4-periphery" rev-parse --short HEAD)"
