#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUTDIR="$(node -p 'require("./docs/config.js").outputDir')"

if [ ! -d node_modules ]; then
  npm ci
fi

examples_source_dir="contracts/mocks/docs"
examples_target_dir="docs/modules/api/examples"

prepare() {
  echo "[prepare-docs] preparing docs..."

  rm -rf "$OUTDIR"
  hardhat docgen

  rm -rf "$examples_target_dir"
  mkdir -p "$examples_target_dir"

  for f in "$examples_source_dir"/**/*.sol; do
    name="${f/#"$examples_source_dir/"/}"
    mkdir -p "$examples_target_dir/$(dirname "$name")"
    sed -Ee '/^import/s|"(\.\./)+|"@openzeppelin/community-contracts/|' "$f" > "$examples_target_dir/$name"
  done
}

prepare
