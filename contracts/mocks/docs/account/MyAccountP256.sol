// contracts/MyAccountP256.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccountP256} from "../../../account/extensions/draft-AccountP256.sol";

contract MyAccountP256 is AccountP256, Initializable {
    /**
     * NOTE: EIP-712 domain is set at construction because each account clone
     * will recalculate its domain separator based on their own address.
     */
    constructor() EIP712("MyAccountP256", "1") {
        _disableInitializers();
    }

    function initializeSigner(bytes32 qx, bytes32 qy) public virtual initializer {
        _initializeSigner(qx, qy);
    }
}
