#!/usr/bin/env node

import cp from 'child_process';
import fs from 'fs';
import path from 'path';
import format from '@openzeppelin/contracts/scripts/generate/format-lines.js';

function getVersion(path) {
  try {
    return fs.readFileSync(path, 'utf8').match(/\/\/ OpenZeppelin Contracts \(last updated v[^)]+\)/)[0];
  } catch {
    return null;
  }
}

async function generateFromTemplate(file, template, outputPrefix = '', lint = false) {
  const script = path.relative(path.join(import.meta.dirname, '../..'), import.meta.filename);
  const input = path.join(path.dirname(script), template);
  const output = path.join(outputPrefix, file);
  const version = getVersion(output);
  const content = format(
    '// SPDX-License-Identifier: MIT',
    ...(version ? [version + ` (${file})`] : []),
    `// This file was procedurally generated from ${input}.`,
    '',
    (await import(template)).default.trimEnd(),
  );

  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, content);
  lint && cp.execFileSync('prettier', ['--write', output]);
}

// Some templates needs to go through the linter after generation
const needsLinter = ['utils/structs/EnumerableMapExtended.sol'];

// Contracts
for (const [file, template] of Object.entries({
  'utils/structs/EnumerableSetExtended.sol': './templates/EnumerableSetExtended.js',
  'utils/structs/EnumerableMapExtended.sol': './templates/EnumerableMapExtended.js',
})) {
  await generateFromTemplate(file, template, './contracts/', needsLinter.includes(file));
}
