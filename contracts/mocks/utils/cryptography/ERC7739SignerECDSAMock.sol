// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../../../utils/cryptography/ERC7739Signer.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract ERC7739SignerECDSAMock is ERC7739Signer, SignerECDSA {
    constructor(address signerAddr) EIP712("ERC7739SignerECDSA", "1") {
        _initializeSigner(signerAddr);
    }
}
