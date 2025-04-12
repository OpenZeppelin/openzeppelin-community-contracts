// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739} from "../../../utils/cryptography/ERC7739.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract ERC7739ECDSAMock is ERC7739, SignerECDSA {
    constructor(address signerAddr) EIP712("ERC7739ECDSA", "1") {
        _setSigner(signerAddr);
    }
}
