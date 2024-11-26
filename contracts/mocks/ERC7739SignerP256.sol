// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7739Signer} from "../utils/cryptography/draft-ERC7739Signer.sol";

contract ERC7739SignerP256 is ERC7739Signer {
    bytes32 private immutable _qx;
    bytes32 private immutable _qy;

    constructor(bytes32 qx, bytes32 qy) EIP712("ERC7739SignerP256", "1") {
        _qx = qx;
        _qy = qy;
    }

    function _validateNestedEIP712Signature(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        bytes32 r = bytes32(signature[0x00:0x20]);
        bytes32 s = bytes32(signature[0x20:0x40]);
        return P256.verify(hash, r, s, _qx, _qy);
    }
}
