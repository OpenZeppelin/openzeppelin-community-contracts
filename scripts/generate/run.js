#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import prettier from 'prettier';
import { Eta } from 'eta';

import * as context from './data.js';

const repoRoot = path.join(import.meta.dirname, '../..');
const templatesDir = path.join(import.meta.dirname, 'templates');
const eta = new Eta({ views: templatesDir, autoEscape: false, autoTrim: false, defaultExtension: '' });

for (const [filepath, needsPrettier] of Object.entries({
  'contracts/utils/structs/EnumerableSetExtended.sol': false,
  'contracts/utils/structs/EnumerableMapExtended.sol': true,
})) {
  console.log(`Generating ${filepath}...`);
  const template = `${path.basename(filepath)}.eta`;
  const input = path.relative(repoRoot, path.join(templatesDir, template));
  const version =
    fs.existsSync(filepath) &&
    fs.readFileSync(filepath, 'utf8').match(/^\/\/ OpenZeppelin Contracts \(last updated v[^)]+\) \([^)]+\)$/m)?.[0];
  const content = [
    '// SPDX-License-Identifier: MIT',
    ...(version ? [version] : []),
    `// This file was procedurally generated from ${input}.`,
    '',
    eta.render(template, context),
  ].join('\n');

  await (
    needsPrettier
      ? prettier
          .resolveConfig(filepath)
          .then(prettierConfig => prettier.format(content, { ...prettierConfig, filepath }))
      : Promise.resolve(content)
  ).then(formatted => {
    fs.mkdirSync(path.dirname(filepath), { recursive: true });
    fs.writeFileSync(filepath, formatted);
  });
}
