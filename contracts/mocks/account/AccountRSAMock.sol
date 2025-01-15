// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {SignerRSA} from "../../utils/cryptography/SignerRSA.sol";

abstract contract AccountRSAMock is Account, SignerRSA {
    constructor(bytes memory e, bytes memory n) {
        _initializeSigner(e, n);
    }
}
