The upgradeable variant of OpenZeppelin Community Contracts is automatically generated from the original Solidity code. We call this process "transpilation" and it is implemented by our [Upgradeability Transpiler](https://github.com/OpenZeppelin/openzeppelin-transpiler/).

When the `master` branch or `release-v*` branches are updated, the code is transpiled and pushed to the corresponding `<branch>-upgradeable` branch of this repository (e.g. `master-upgradeable`) by the `upgradeable.yml` workflow. Each of these branches includes the original code as a submodule in `lib/openzeppelin-community-contracts`.

## `transpile.sh`

Applies patches and invokes the transpiler with the settings in `transpile.config.json` (for example, excluding certain files).

## `transpile.js`

Unlike OpenZeppelin Contracts, this library builds on contracts it doesn't own. This script runs the transpiler on the compiled sources, keeps the output for `contracts/` only, and rewrites its imports:

- Stateful contracts from `@openzeppelin/contracts` are imported from `@openzeppelin/contracts-upgradeable`.
- Stateless declarations (interfaces, libraries, etc.) are imported from their original package, including `@openzeppelin/community-contracts` for the ones in this repository.

A stateful contract from any other package has no upgradeable variant, so the files that use it must be excluded in `transpile.config.json`. Files that are excluded or not transpiled are imported in `contracts/mocks/PeerImports.sol` so they remain available to the tests.

## `transpile-onto.sh`

```
bash scripts/upgradeable/transpile-onto.sh <target> [<base>]
```

Transpiles the contents of the current git branch and commits the result as a new commit on branch `<target>`. If branch `<target>` doesn't exist, it will copy the commit history of `[<base>]` (this is used in GitHub Actions, but is usually not necessary locally).

## `patch-apply.sh` & `patch-save.sh`

Some of the upgradeable contract variants require ad-hoc changes that are not implemented by the transpiler. These changes are implemented by patches stored in `upgradeable.patch` in this directory. `patch-apply.sh` applies these patches.

If the patches fail to apply due to changes in the repo, the conflicts have to be resolved manually. Once fixed, `patch-save.sh` will take the changes staged in Git and update `upgradeable.patch` to match.
