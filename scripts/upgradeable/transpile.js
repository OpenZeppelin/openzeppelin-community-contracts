#!/usr/bin/env node

// Transpiles `contracts/` using the build info produced by `hardhat compile`.
//
// Unlike OpenZeppelin Contracts, this library depends on contracts it does not own (`@openzeppelin/contracts` and
// third party packages). These sources must remain part of the transpilation so that symbols can be resolved, but
// their transpiled output is discarded. Imports in the transpiled files are then rewritten so that:
// - Stateful contracts from `@openzeppelin/contracts` are imported from `@openzeppelin/contracts-upgradeable`.
// - Stateless declarations (interfaces, libraries, free functions, etc.) are imported from their original package.

const fs = require('fs');
const path = require('path');
const { transpile } = require('@openzeppelin/upgrade-safe-transpiler');
const { findAlreadyInitializable } = require('@openzeppelin/upgrade-safe-transpiler/dist/find-already-initializable');

const SOURCES = 'contracts';
const PEER_PLACEHOLDER = '__peer__';
const PACKAGES = {
  [SOURCES + '/']: '@openzeppelin/community-contracts/',
};
const UPGRADEABLE_PACKAGES = {
  '@openzeppelin/contracts/': '@openzeppelin/contracts-upgradeable/',
};

const settingsPath = process.argv[2] ?? path.join(__dirname, 'transpile.config.json');
const { initializablePath, ...settings } = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

const root = process.cwd();
const buildInfoDir = path.join(root, 'artifacts', 'build-info');
const buildInfos = fs.readdirSync(buildInfoDir);
if (buildInfos.length !== 1) {
  throw new Error(`Expected ${buildInfoDir} to contain only one file`);
}
const { input, output, solcVersion } = JSON.parse(fs.readFileSync(path.join(buildInfoDir, buildInfos[0]), 'utf8'));

const isLocal = file => file.startsWith(SOURCES + '/');

// Contracts that already inherit from `Initializable` are left untouched. The transpiler would exclude them from the
// transformation, but dependencies must stay included for their symbols to be resolved. Instead, `initializablePath` is
// handled here and only local files are excluded. The transpiler then defaults to importing `Initializable` from
// `contracts/Initializable.sol` (as a peer), which is redirected to `initializablePath`.
const alreadyInitializable = findAlreadyInitializable(output, initializablePath);
const DEFAULT_INITIALIZABLE = path.join(PEER_PLACEHOLDER, SOURCES, 'Initializable.sol');

// Maps an import path produced by the transpiler to its final location.
function resolveImport(file, importPath) {
  if (importPath === DEFAULT_INITIALIZABLE) {
    return initializablePath;
  }
  if (importPath.startsWith(PEER_PLACEHOLDER + '/')) {
    const original = importPath.slice(PEER_PLACEHOLDER.length + 1);
    const prefix = Object.keys(PACKAGES).find(p => original.startsWith(p));
    return prefix ? PACKAGES[prefix] + original.slice(prefix.length) : original;
  }
  if (importPath.startsWith('.')) {
    return importPath;
  }
  const prefix = Object.keys(UPGRADEABLE_PACKAGES).find(p => importPath.startsWith(p));
  if (prefix === undefined) {
    throw new Error(`${file} imports a stateful contract from ${importPath}, which has no upgradeable variant`);
  }
  return UPGRADEABLE_PACKAGES[prefix] + importPath.slice(prefix.length);
}

function rewriteImports(file, source) {
  return source.replace(/^(import\s[^;]*?["'])([^"']+)(["'];)/gm, (_, pre, importPath, post) =>
    [pre, resolveImport(file, importPath), post].join(''),
  );
}

// The generated `WithInit` file contains a block for every transformed contract, including those from dependencies.
// Only the blocks corresponding to local contracts are kept. Their imports are restricted to the contract and the
// user-defined types of its constructor arguments, to avoid clashes between symbols the imported files bring into scope.
const ELEMENTARY_TYPES = /^(address|bool|string|bytes\d*|u?int\d*|u?fixed[\dx]*)$/;

function filterWithInit(file, source) {
  const [header, ...blocks] = source.split(/^(?=import ")/m);
  const kept = blocks
    .map(block => {
      const [, importPath, name, params] = block.match(
        /^import "([^"]+)";\s+contract \w+ is (\w+) {\s+constructor\(([^)]*)\)/,
      );
      const types = params
        .split(',')
        .map(param => param.trim().match(/^\w+/)?.[0])
        .filter(type => type && !ELEMENTARY_TYPES.test(type));
      const symbols = [...new Set([name, ...types])];
      return { importPath, block: block.replace(/^import "/, `import {${symbols.join(', ')}} from "`) };
    })
    .filter(({ importPath }) => isLocal(path.join(path.dirname(file), importPath)))
    .map(({ block }) => block);
  return [header, ...kept].join('');
}

// Transpiling with a peer project requires every import to list its symbols. Dependencies are only transformed so their
// symbols can be resolved and their output is discarded, so their unaliased imports are expanded to every exported symbol.
for (const [source, { ast }] of Object.entries(output.sources)) {
  if (isLocal(source)) continue;
  for (const node of ast.nodes) {
    if (node.nodeType === 'ImportDirective' && node.symbolAliases.length === 0 && node.unitAlias === '') {
      const { exportedSymbols } = output.sources[node.absolutePath].ast;
      node.symbolAliases = Object.keys(exportedSymbols).map(name => ({ foreign: { name }, local: null }));
    }
  }
}

async function main() {
  const files = await transpile(
    input,
    output,
    { root, sources: path.join(root, SOURCES) },
    {
      ...settings,
      exclude: [...(settings.exclude ?? []), ...alreadyInitializable.filter(isLocal)],
      solcVersion,
      peerProject: PEER_PLACEHOLDER + '/',
    },
  );

  const withInitPath = path.join(SOURCES, 'mocks', 'WithInit.sol');
  const results = files
    .filter(t => isLocal(t.path))
    .map(t => ({
      path: t.path,
      source: t.path === withInitPath ? filterWithInit(t.path, t.source) : rewriteImports(t.path, t.source),
    }));

  for (const { path: file, source } of results) {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.writeFileSync(path.join(root, file), source);
  }

  if (settings.deleteOriginals) {
    const keep = new Set([...results.map(t => t.path), ...alreadyInitializable]);
    const deleted = Object.keys(output.sources).filter(source => isLocal(source) && !keep.has(source));
    for (const source of deleted) {
      fs.rmSync(path.join(root, source), { force: true });
    }

    // Files without an upgradeable variant are imported from the peer project, so they are compiled (and exposed) for
    // the tests. Files that only contain imports (e.g. `mocks/import.sol`) have their imported symbols forwarded. Names
    // declared in more than one file are aliased to avoid clashes.
    const declarations = deleted.map(source => {
      const { nodes } = output.sources[source].ast;
      const contracts = nodes.filter(n => n.nodeType === 'ContractDefinition').map(n => n.name);
      const imported = nodes
        .filter(n => n.nodeType === 'ImportDirective')
        .flatMap(n => n.symbolAliases.map(a => a.local ?? a.foreign.name));
      return { source, names: contracts.length > 0 ? contracts : imported };
    });
    const count = {};
    declarations.flatMap(({ names }) => names).forEach(name => (count[name] = (count[name] ?? 0) + 1));
    const peerImports = [
      '// SPDX-License-Identifier: UNLICENSED',
      'pragma solidity ^0.8.20;',
      '',
      ...declarations
        .filter(({ names }) => names.length > 0)
        .map(({ source, names }, i) => {
          const symbols = names.map(name => (count[name] > 1 ? `${name} as ${name}_${i}` : name));
          return `import {${symbols.join(', ')}} from "${resolveImport(source, path.join(PEER_PLACEHOLDER, source))}";`;
        }),
      '',
    ];
    fs.writeFileSync(path.join(root, SOURCES, 'mocks', 'PeerImports.sol'), peerImports.join('\n'));
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
