// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EmailProof} from "@zk-email/email-tx-builder/src/interfaces/IVerifier.sol";
import {IVerifier} from "../../../utils/cryptography/ZKEmailUtils.sol";

contract ZKEmailVerifierMock is IVerifier {
    function commandBytes() external pure returns (uint256) {
        // Same as in https://github.com/zkemail/email-tx-builder/blob/1452943807a5fdc732e1113c34792c76cf7dd031/packages/contracts/src/utils/Verifier.sol#L15
        return 605;
    }

    function verifyEmailProof(bytes memory proof) external pure returns (bool) {
        EmailProof memory emailProof = abi.decode(proof, (EmailProof));
        return emailProof.proof.length > 0 && bytes1(emailProof.proof[0]) == 0x01; // boolean true
    }
}
