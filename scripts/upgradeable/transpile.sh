#!/usr/bin/env bash

set -euo pipefail -x

DIRNAME="$(dirname -- "${BASH_SOURCE[0]}")"

# apply patches to the codebase
bash "$DIRNAME/patch-apply.sh"

# compile and run the transpiler
npm run clean
npx hardhat compile
node "$DIRNAME/transpile.js" "$DIRNAME/transpile.config.json"

# delete compilation artifacts of vanilla code
npm run clean
