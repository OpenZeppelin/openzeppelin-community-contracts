#!/usr/bin/env bash

# This file is an exact copy of lib/@openzeppelin-contracts/scripts/checks/generation.sh.

set -euo pipefail

npm run generate
git diff -R --exit-code
