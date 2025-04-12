#!/usr/bin/env node

const cp = require('child_process');
const fs = require('fs');
const path = require('path');
const format = require('@openzeppelin/contracts/scripts/generate/format-lines');

function getVersion(path) {
  try {
    return fs.readFileSync(path, 'utf8').match(/\/\/ OpenZeppelin Community Contracts \(last updated v[^)]+\)/)[0];
  } catch {
    return null;
  }
}

function generateFromTemplate(file, template, outputPrefix = '') {
  const script = path.relative(path.join(__dirname, '../..'), __filename);
  const input = path.join(path.dirname(script), template);
  const output = path.join(outputPrefix, file);
  const version = getVersion(output);
  const content = format(
    '// SPDX-License-Identifier: MIT',
    ...(version ? [version + ` (${file})`] : []),
    `// This file was procedurally generated from ${input}.`,
    '',
    require(template).trimEnd(),
  );
  fs.writeFileSync(output, content);
  cp.execFileSync('prettier', ['--write', output]);
}

// Contracts
for (const [file, template] of Object.entries({
  'utils/structs/EnumerableSetExtended.sol': './templates/EnumerableSetExtended.js',
  'utils/structs/EnumerableMapExtended.sol': './templates/EnumerableMapExtended.js',
})) {
  generateFromTemplate(file, template, './contracts/');
}
