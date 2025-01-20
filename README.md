# <img src="logo.svg" alt="OpenZeppelin" height="40px">

[![Forum](https://img.shields.io/badge/forum-%F0%9F%92%AC-yellow)](https://docs.openzeppelin.com/contracts)

> [!IMPORTANT]
> This repository includes community-curated and experimental code that has not been audited and may introduce breaking changes at any time. We recommend
> reviewing the [Security](#security) section before using any code from this repository.

## Overview

This repository contains contracts and libraries in the following categories:

- Extensions and modules compatible with contracts in the [@openzeppelin/contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) package
- Alternative implementation of interfaces defined in the [@openzeppelin/contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) package
- Contracts with third-party integrations
- Contracts built by community members, that align with OpenZeppelin offerings
- General prototypes and experiments

Code is provided by the OpenZeppelin Contracts team, as well as by community contributors, for other developers to review, discuss, iterate on, and potentially use.

## Security

Contracts and libraries in this repository are provided as is, with no particular guarantees. In particular:

- Code in this repository is not audited. Maintainers will review the code to the extend that the is no obviously malicious code published, but bugs may be present in this code that may lead to privilege escalation or loss of funds. Any code taken from this repository should be audited before being used in production.

- Code in this repository is NOT covered by the [OpenZeppelin bug bounty on Immunefi](https://immunefi.com/bug-bounty/openzeppelin/) unless explicitly specified otherwise.

- Code in this repository comes with no backward compatibility guarantees. Updates may change internal or external interfaces without notice. Dependencies updates may also break code present in this repository.

- Code in this repository may depend on un-audited and un-released features from the [OpenZeppelin Contracts repository](https://github.com/OpenZeppelin/openzeppelin-contracts). In some cases, having a versioned dependency on the OpenZeppelin contracts library may not be enough.

- Code in this repository is not versioned nor formally released.

- Bugs affecting code in this repository may not be notified through a CVE.

## Contribute

OpenZeppelin Contracts exists thanks to its contributors. There are many ways you can participate and help build high quality software. Check out the [contribution guide](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/CONTRIBUTING.md)!

### CODEOWNERS

Contributions to this repository require approval from a code owner (see [CODEOWNERS](./.github/CODEOWNERS)). They are responsible for reviewing contributions to their respective areas of the codebase and ensuring that they meet the project's standards for quality and security.

## License

Each contract file should have their own licence specified. In the absence of any specific licence information, file is released under the [MIT License](LICENSE).

## Legal

Your use of this Project is governed by the terms found at www.openzeppelin.com/tos (the "Terms").
