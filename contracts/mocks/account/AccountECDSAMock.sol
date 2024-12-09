// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AccountECDSA} from "../../account/draft-AccountECDSA.sol";

contract AccountECDSAMock is AccountECDSA {
    constructor(string memory name, string memory version, address signerAddr) EIP712(name, version) {
        _initializeSigner(signerAddr);
    }
}
