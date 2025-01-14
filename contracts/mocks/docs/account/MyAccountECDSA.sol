// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "../../../account/Account.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract MyAccountECDSA is Account, SignerECDSA {
    constructor() EIP712("MyAccountECDSA", "1") {}

    function initializeSigner(address signerAddr) public virtual {
        // Will revert if the signer is already initialized
        _initializeSigner(signerAddr);
    }
}
