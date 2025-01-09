// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Account} from "../../../account/Account.sol"; // or AccountCore

contract MyAccount is Account, Initializable {
    /**
     * NOTE: EIP-712 domain is set at construction because each account clone
     * will recalculate its domain separator based on their own address.
     */
    constructor() EIP712("MyAccount", "1") {}

    /// @dev Signature validation logic.
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        // Custom validation logic
    }

    function initializeSigner() public initializer {
        // Most accounts will require some form of signer initialization logic
    }
}
