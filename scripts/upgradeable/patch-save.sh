#!/usr/bin/env bash

# This file is an exact copy of lib/@openzeppelin-contracts/scripts/upgradeable/patch-save.sh.

set -euo pipefail

DIRNAME="$(dirname -- "${BASH_SOURCE[0]}")"
PATCH="$DIRNAME/upgradeable.patch"

error() {
  echo Error: "$*" >&2
  exit 1
}

if ! git diff-files --quiet ":!$PATCH"; then
  error "Unstaged changes. Stage to include in patch or temporarily stash."
fi

git diff-index --cached --patch --output="$PATCH" HEAD
git restore --staged --worktree ":!$PATCH"
