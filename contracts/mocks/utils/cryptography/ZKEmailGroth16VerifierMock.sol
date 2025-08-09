// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";

contract ZKEmailGroth16VerifierMock is IGroth16Verifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[34] calldata /* _pubSignals */
    ) public pure returns (bool) {
        return
            _pA[0] == 1 &&
            _pA[1] == 2 &&
            _pB[0][0] == 3 &&
            _pB[0][1] == 4 &&
            _pB[1][0] == 5 &&
            _pB[1][1] == 6 &&
            _pC[0] == 7 &&
            _pC[1] == 8;
    }
}
