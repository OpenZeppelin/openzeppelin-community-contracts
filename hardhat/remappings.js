const fs = require('fs');
const { task } = require('hardhat/config');
const { TASK_COMPILE_GET_REMAPPINGS } = require('hardhat/builtin-tasks/task-names');

const UPDATED_VENDORED_REMAPPINGS = 'vendor';

const remappings = Object.fromEntries(
  fs
    .readFileSync('remappings.txt', 'utf-8')
    .split('\n')
    .filter(Boolean)
    .filter(line => !line.startsWith('#'))
    .map(line => line.trim().split('=')),
);

task(TASK_COMPILE_GET_REMAPPINGS).setAction((taskArgs, env, runSuper) =>
  runSuper().then(r => Object.assign(r, remappings)),
);

task(UPDATED_VENDORED_REMAPPINGS).setAction(() => {
  const NODE_MODULES_PATH = 'node_modules/';
  const LIB_PATH = 'lib/';

  for (const [, src] of Object.entries(remappings).filter(r => r[1].includes(NODE_MODULES_PATH))) {
    const dir = src.replace(NODE_MODULES_PATH, LIB_PATH);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.cpSync(src, dir, { recursive: true });
  }

  const vendoredRemappings = Object.entries(remappings)
    .map(r => [r[0], r[1].replace(NODE_MODULES_PATH, LIB_PATH)])
    .map(r => `${r[0]}=${r[1]}`)
    .join('\n');

  fs.writeFileSync('remappings.txt', vendoredRemappings);
});
