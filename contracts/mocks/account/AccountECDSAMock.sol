// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {SignerECDSA} from "../../utils/cryptography/SignerECDSA.sol";

abstract contract AccountECDSAMock is Account, SignerECDSA, ERC7821 {
    constructor(address signerAddr) {
        _initializeSigner(signerAddr);
    }
}
