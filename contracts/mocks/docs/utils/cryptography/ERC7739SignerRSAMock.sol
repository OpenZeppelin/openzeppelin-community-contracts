// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../../../../utils/cryptography/draft-ERC7739Signer.sol";

contract ERC7739SignerRSAMock is ERC7739Signer {
    bytes private _e;
    bytes private _n;

    constructor(bytes memory e, bytes memory n) EIP712("ERC7739SignerRSA", "1") {
        _e = e;
        _n = n;
    }

    function _validateSignature(bytes32 hash, bytes calldata signature) internal view virtual override returns (bool) {
        return RSA.pkcs1Sha256(hash, signature, _e, _n);
    }
}
