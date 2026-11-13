import path from 'node:path';

import type { HardhatPlugin } from 'hardhat/types/plugins';

/**
 * Remappings that apply to Hardhat only, on top of the ones of `remappings.txt` (which Foundry also reads). They are
 * given precedence: Hardhat keeps the first remapping of a given context and prefix.
 *
 * Only the project itself is affected, not its npm dependencies. Remappings are resolved relative to the project root.
 */
export default function hardhatRemappings(remappings: string[]): HardhatPlugin {
  return {
    id: 'hardhat-remappings',
    hookHandlers: {
      solidity: async () => ({
        default: async () => ({
          readNpmPackageRemappings: async (context, packageName, packageVersion, packagePath, next) => {
            const sources = await next(context, packageName, packageVersion, packagePath);
            return packagePath === context.config.paths.root
              ? [{ remappings, source: path.join(packagePath, 'remappings.txt') }, ...sources]
              : sources;
          },
        }),
      }),
    },
  };
}
