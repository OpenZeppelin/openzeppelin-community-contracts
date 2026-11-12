#!/usr/bin/env bash

# This file is an exact copy of lib/@openzeppelin-contracts/scripts/git-user-config.sh.

set -euo pipefail -x

git config user.name 'github-actions'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
