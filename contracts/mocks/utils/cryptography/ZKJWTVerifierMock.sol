// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IVerifier, EmailProof} from "@zk-email/zk-jwt/src/interfaces/IVerifier.sol";

contract ZKJWTVerifierMock is IVerifier {
    function getCommandBytes() external pure returns (uint256) {
        // Same as in https://github.com/zkemail/zk-jwt/blob/27436a2f23e78e89cf624f649ec1d125f13772dd/packages/contracts/src/utils/JwtVerifier.sol#L20
        return 605;
    }

    function verifyEmailProof(EmailProof memory proof) external pure returns (bool) {
        return proof.proof.length > 0 && bytes1(proof.proof[0]) == 0x01; // boolean true
    }
}
