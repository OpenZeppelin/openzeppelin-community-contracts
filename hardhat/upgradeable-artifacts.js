// Resolves contract names to their transpiled variants (if any), so tests can run on the upgradeable version of the
// library without modifications.
const { extendEnvironment } = require('hardhat/config');

const suffixes = ['UpgradeableWithInit', 'Upgradeable'];

extendEnvironment(hre => {
  const { artifacts } = hre;
  const readArtifact = artifacts.readArtifact.bind(artifacts);
  const readArtifactSync = artifacts.readArtifactSync.bind(artifacts);

  artifacts.readArtifact = async name => {
    for (const suffix of suffixes) {
      if (await artifacts.artifactExists(name + suffix)) return readArtifact(name + suffix);
    }
    return readArtifact(name);
  };

  artifacts.readArtifactSync = name => {
    for (const suffix of suffixes) {
      try {
        return readArtifactSync(name + suffix);
      } catch {
        // try the next suffix
      }
    }
    return readArtifactSync(name);
  };
});
