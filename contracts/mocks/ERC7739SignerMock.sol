// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../utils/cryptography/draft-ERC7739Signer.sol";

contract ERC7739SignerMock is ERC7739Signer {
    address private immutable _eoa;

    constructor(address eoa) EIP712("ERC7739SignerMock", "1") {
        _eoa = eoa;
    }

    function _validateSignature(bytes32 hash, bytes calldata signature) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return _eoa == recovered && err == ECDSA.RecoverError.NoError;
    }
}
