// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccountRSA} from "../../account/extensions/draft-AccountRSA.sol";

abstract contract AccountRSAMock is AccountRSA {
    constructor(bytes memory e, bytes memory n) {
        _initializeSigner(e, n);
    }
}
