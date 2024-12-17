// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../../../utils/cryptography/ERC7739Signer.sol";
import {SignerRSA} from "../../../utils/cryptography/SignerRSA.sol";

contract ERC7739SignerRSAMock is ERC7739Signer, SignerRSA {
    constructor(bytes memory e, bytes memory n) EIP712("ERC7739SignerRSA", "1") {
        _initializeSigner(e, n);
    }
}
