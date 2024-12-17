// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../../../utils/cryptography/ERC7739Signer.sol";
import {SignerP256} from "../../../utils/cryptography/SignerP256.sol";

contract ERC7739SignerP256Mock is ERC7739Signer, SignerP256 {
    constructor(bytes32 qx, bytes32 qy) EIP712("ERC7739SignerP256", "1") {
        _initializeSigner(qx, qy);
    }
}
