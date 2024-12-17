// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {SignerECDSA} from "../../utils/cryptography/SignerECDSA.sol";

abstract contract AccountECDSAMock is Account, SignerECDSA {
    constructor(address signerAddr) {
        _initializeSigner(signerAddr);
    }
}
