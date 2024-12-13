// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccountECDSA} from "../../account/extensions/draft-AccountECDSA.sol";

abstract contract AccountECDSAMock is AccountECDSA {
    constructor(address signerAddr) {
        _initializeSigner(signerAddr);
    }
}
