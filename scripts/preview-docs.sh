#!/usr/bin/env bash

set -euo pipefail
cd $(dirname $0)/..
ROOT=$(pwd)
REPO_DOCS=$ROOT/docs
COMPANY_DOCS=$ROOT/docs/docs
rm -rf $COMPANY_DOCS
cd $REPO_DOCS
git clone --depth 1 https://github.com/OpenZeppelin/docs.git
cp -r $REPO_DOCS/modules/api/pages/*  $COMPANY_DOCS/content/community-contracts/api
cp -r $REPO_DOCS/modules/api/examples $COMPANY_DOCS/content/community-contracts/api 
cd $COMPANY_DOCS
pnpm i
pnpm run build
#pnpm run dev