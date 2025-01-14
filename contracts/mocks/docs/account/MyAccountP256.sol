// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "../../../account/Account.sol";
import {AbstractSigner, SignerP256} from "../../../utils/cryptography/SignerP256.sol";

contract MyAccountP256 is Account, SignerP256 {
    constructor() EIP712("MyAccountP256", "1") {}

    function initializeSigner(bytes32 qx, bytes32 qy) public virtual {
        // Will revert if the signer is already initialized
        _initializeSigner(qx, qy);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, SignerP256) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
