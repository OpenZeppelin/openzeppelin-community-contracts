// contracts/MyAccountRSA.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccountRSA} from "../../../account/extensions/draft-AccountRSA.sol";

contract MyAccountRSA is AccountRSA, Initializable {
    /**
     * NOTE: EIP-712 domain is set at construction because each account clone
     * will recalculate its domain separator based on their own address.
     */
    constructor() EIP712("MyAccountRSA", "1") {
        _disableInitializers();
    }

    function initializeSigner(bytes memory e, bytes memory n) public virtual initializer {
        _initializeSigner(e, n);
    }
}
