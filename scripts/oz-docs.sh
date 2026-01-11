#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DOCS="$ROOT/docs"
OZ_DOCS="$DOCS/oz-docs"
OUTDIR="$OZ_DOCS/content/community-contracts/api"

CHOKIDAR_BIN="$ROOT/node_modules/.bin/chokidar"
PREPARE="$ROOT/scripts/prepare-docs.sh"

# Attempt to update the cached docs repo, or clone it if it doesn't exist.
init() {
  if [ -d "$OZ_DOCS/.git" ]; then
    echo "[oz-docs] updating cached docs repo..."
    cd "$OZ_DOCS"
    git fetch origin main
    git reset --hard origin/main
    git clean -fd
  else
    echo "[oz-docs] cloning docs repo..."
    rm -rf "$OZ_DOCS"
    cd "$DOCS"
    git clone --branch main https://github.com/OpenZeppelin/docs.git oz-docs
    cd "$OZ_DOCS"
  fi

  pnpm i
}

# Prepare the docs.
prepare() {
  echo "[oz-docs] preparing docs..."
  bash "$PREPARE"
}

# Sync the locally prepared docs into the local docs project.
sync() {
  echo "[oz-docs] syncing docs..."
  mkdir -p "$OUTDIR"
  rsync -a --delete "$DOCS/modules/api/pages/" "$OUTDIR/"
  mkdir -p "$OUTDIR/examples"
  rsync -a --delete "$DOCS/modules/api/examples/" "$OUTDIR/examples/"
}

# Entry point used by the watcher (sync only).
if [ "${SYNC_ONCE:-false}" = "true" ]; then
  sync
  exit 0
fi

# One-time setup.
init
prepare
sync

# Watch for changes, then prepare and sync.
if [ "${WATCH:-false}" = "true" ]; then
  if [ ! -x "$CHOKIDAR_BIN" ]; then
    echo "error: chokidar-cli not found (run: npm i -D chokidar-cli)" >&2
    exit 1
  fi

  cd "$ROOT"

  echo "[oz-docs] watching for changes..."
  "$CHOKIDAR_BIN" \
    "contracts/**/*.{sol,mdx}" \
    "docs/config.js" \
    "docs/templates/**/*" \
    --ignoreInitial \
    --throttle 500 \
    --debounce 400 \
    -c "echo '[oz-docs] change detected'; bash '$PREPARE'; SYNC_ONCE=true WATCH=false bash '$ROOT/scripts/oz-docs.sh'" &

  cd "$OZ_DOCS"
  pnpm run dev
else
  cd "$OZ_DOCS"
  pnpm run build
fi
