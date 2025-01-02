// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "@openzeppelin/community-contracts/account/Account.sol";
import {SignerRSA} from "@openzeppelin/community-contracts/utils/cryptography/SignerRSA.sol";

contract MyAccountRSA is Account, SignerRSA {
    constructor() EIP712("MyAccountRSA", "1") {}

    function initializeSigner(bytes memory e, bytes memory n) public virtual {
        // Will revert if the signer is already initialized
        _initializeSigner(e, n);
    }
}
