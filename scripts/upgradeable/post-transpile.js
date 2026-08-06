#!/usr/bin/env node
// Post-transpile fix-ups, run after the upgrade-safe-transpiler. Operates on the transpiler's in-place
// output under contracts/, plus the dependency copies it emits at the repo root.
//
// TODOs for @openzeppelin/upgrade-safe-transpiler:
//   * TODO-1: Reuse a dependency's already-published upgradeable counterpart: remap imports to it, don't re-transpile
//   * TODO-2: Transpile a configurable vendor output dir for deps with NO published upgradeable: emit there + fix imports
//   * TODO-3: Peer as a per-dependency source-prefix -> package map, so scoped deps aren't double-prefixed
//   * TODO-4: WithInit generation should skip abstract contracts
//   * TODO-5: The add-namespace-struct should strip visibility from a var it moves into the storage struct  [see transpile.sh]
//
// Current script can be removed when all @openzeppelin/upgrade-safe-transpiler TODOs are done.

const fs = require('fs');
const path = require('path');

const DEPS = ['@axelar-network', 'wormhole-solidity-sdk'];
const VENDOR = 'contracts/vendor';

// Discard the regenerated vanilla OZ copy — its imports are redirected to
// @openzeppelin/contracts-upgradeable in the fix-ups below. (To remove when TODO-1 is done.)
fs.rmSync('@openzeppelin', { recursive: true, force: true });

// Move the generated Axelar/Wormhole trees under contracts/vendor/ (BEFORE the import fix-ups so their own
// imports get cleaned up too). (To remove when TODO-2 is done.)
for (const dep of DEPS) {
  if (!fs.existsSync(dep)) continue;
  fs.cpSync(dep, path.join(VENDOR, dep), { recursive: true });
  fs.rmSync(dep, { recursive: true, force: true });
}

// Import fix-ups (applied to every contracts/**/*.sol).
const vendorRe = new RegExp(`(["'])(?:\\.\\./)*((?:${DEPS.join('|')})/[^"']*Upgradeable\\.sol)\\1`, 'g');
const fixImports = (file, src) =>
  src
    // Repoint imports of the files we just vendored. The transpiler generated these *Upgradeable contracts
    // and left importers pointing at the original dependency path, in two forms:
    //     "@axelar-network/.../AxelarExecutableUpgradeable.sol"       (from our own contracts)
    //     "../../@axelar-network/.../AxelarExecutableUpgradeable.sol" (from the generated mocks/WithInit.sol)
    // Rewrite both to a path relative to the importing file that points into contracts/vendor/. It MUST be
    // relative: keeping the "@axelar-network/..." form would resolve to the consumer's real Axelar package
    // (which has no *Upgradeable files) instead of our vendored copy. In the regex, (?:\.\./)* eats any
    // leading "../" so both forms match, and the captured group is the "<dep>/.../X.sol" tail.
    // (To remove when TODO-2 is done.)
    .replace(vendorRe, (_m, quote, target) => {
      const rel = path.relative(path.dirname(file), path.join(VENDOR, target));
      return quote + (rel.startsWith('.') ? rel : './' + rel) + quote;
    })
    // Strip the @openzeppelin/community-contracts/ prefix the peer step wrongly prepended to third-party
    // stateless files ((?!contracts/) protects our own files) -> vanilla/axelar/wormhole interfaces resolve
    // to lib/ again. (To remove when TODO-3 is done.)
    .replace(/"@openzeppelin\/community-contracts\/(?!contracts\/)([^"]*)"/g, '"$1"')
    // Redirect the regenerated vanilla *Upgradeable to the published @openzeppelin/contracts-upgradeable.
    // (To remove when TODO-1 is done.)
    .replace(
      /"(?:\.\.\/)*@openzeppelin\/contracts\/([^"]*Upgradeable\.sol)"/g,
      '"@openzeppelin/contracts-upgradeable/$1"',
    );

// DKIMRegistry is abstract, so its WithInit wrapper is useless (can't deploy an abstract contract) and its
// bare import drags in our ERC-7969 IDKIMRegistry, name-clashing with zk-email's same-named one (the clash
// resurfaces in hardhat-exposed's re-exposed copy too). Drop the wrapper (import + contract block).
// (To remove when TODO-4 is done.)
const fixWithInit = src =>
  src
    .replace(/^import "[^"]*\/DKIMRegistryUpgradeable\.sol";\n/m, '')
    .replace(/^contract DKIMRegistryUpgradeableWithInit is DKIMRegistryUpgradeable \{\n[\s\S]*?^\}\n/m, '');

const walk = dir =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const p = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(p) : p.endsWith('.sol') ? [p] : [];
  });

for (const file of walk('contracts')) {
  const src = fs.readFileSync(file, 'utf8');
  let out = fixImports(file, src);
  if (file.replace(/\\/g, '/').endsWith('mocks/WithInit.sol')) out = fixWithInit(out);
  if (out !== src) fs.writeFileSync(file, out);
}
