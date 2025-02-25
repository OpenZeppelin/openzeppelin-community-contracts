// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC7579SocialRecoveryExecutor} from "../../../account/extensions/ERC7579Modules/ERC7579SocialRecoveryExecutor.sol";

contract ERC7579SocialRecoveryExecutorMock is ERC7579SocialRecoveryExecutor {
    constructor(string memory name, string memory version) ERC7579SocialRecoveryExecutor(name, version) {}

    // helper for testing signature validation
    function validateGuardianSignatures(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes32 digest
    ) public view virtual {
        super._validateGuardianSignatures(account, guardianSignatures, digest);
    }
}
