// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccountP256} from "../../account/extensions/draft-AccountP256.sol";

abstract contract AccountP256Mock is AccountP256 {
    constructor(bytes32 qx, bytes32 qy) {
        _initializeSigner(qx, qy);
    }
}
