// contracts/MyAccountECDSA.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccountECDSA} from "../../../account/draft-AccountECDSA.sol";

contract MyAccountECDSA is AccountECDSA, Initializable {
    /**
     * NOTE: EIP-712 domain is set at construction because each account clone
     * will recalculate its domain separator based on their own address.
     */
    constructor() EIP712("MyAccountECDSA", "1") {
        _disableInitializers();
    }

    function initializeSigner(address signerAddr) public virtual initializer {
        _initializeSigner(signerAddr);
    }
}
