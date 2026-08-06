#!/usr/bin/env bash

set -euo pipefail -x

VERSION="$(jq -r .version package.json)"
DIRNAME="$(dirname -- "${BASH_SOURCE[0]}")"

bash "$DIRNAME/patch-apply.sh"

sed -i'' -e "s/<package-version>/$VERSION/g" "package.json"
git add package.json

npm run clean
npm run compile

build_info=($(jq -r '.input.sources | keys | if any(test("^contracts/mocks/.*\\bunreachable\\b")) then empty else input_filename end' artifacts/build-info/*))
build_info_num=${#build_info[@]}

if [ $build_info_num -ne 1 ]; then
  echo "found $build_info_num relevant build info files but expected just 1"
  exit 1
fi

# -D: delete original and excluded files
# -b: use this build info file
# -x: exclude contracts from transpilation entirely
# -N: exclude from namespaces transformation
#     The -N '@axelar-network/**/*' / -N 'wormhole-solidity-sdk/**/*' excludes below are only needed because
#     add-namespace-struct keeps `internal` on a var moved into the ERC-7201 struct (invalid Solidity).
#     (To remove when TODO-5 is done)
# -n: use namespaces
# -q: partial transpilation (peer mode) so stateless files (interfaces/libraries) are left untranspiled
#     and imported from a peer package instead. The peer path is path.join('@openzeppelin/community-contracts',
#     <file path>): OUR OWN stateless files (contracts/utils/Masks.sol) correctly become
#     @openzeppelin/community-contracts/contracts/utils/Masks.sol (reused from the published non-upgradeable
#     package, like contracts-upgradeable reuses @openzeppelin/contracts). The side effect is that vanilla /
#     axelar / wormhole stateless files get DOUBLE-prefixed
#     (@openzeppelin/community-contracts/@openzeppelin/contracts/...); the post-processing below strips that.
npx @openzeppelin/upgrade-safe-transpiler -D \
  -b "$build_info" \
  -i '@openzeppelin/contracts/proxy/utils/Initializable.sol' \
  -x 'contracts-exposed/**/*' \
  -x '@openzeppelin/contracts/proxy/**/*Proxy*.sol' \
  -x '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol' \
  -x '@openzeppelin/contracts/mocks/**/*Proxy*.sol' \
  -x 'contracts/proxy/**/*' \
  -N '@openzeppelin/contracts-upgradeable/**/*' \
  -N '@openzeppelin/contracts/**/*' \
  -N '@axelar-network/**/*' \
  -N 'wormhole-solidity-sdk/**/*' \
  -n \
  -N 'contracts/mocks/**/*' \
  -q '@openzeppelin/community-contracts'

# Post-transpile fix-ups: discard the regenerated vanilla OZ copy, vendor Axelar/Wormhole under
# contracts/vendor/, rewrite dependency imports, and drop the abstract DKIMRegistry WithInit wrapper.
# See post-transpile.js for details.
node "$DIRNAME/post-transpile.js"

# delete compilation artifacts of vanilla code
npm run clean
