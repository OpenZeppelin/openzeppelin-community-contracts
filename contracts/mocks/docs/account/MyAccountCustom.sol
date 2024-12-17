// contracts/MyAccountCustom.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Account} from "../../../account/Account.sol";

contract MyAccountCustom is Account, Initializable {
    /**
     * NOTE: EIP-712 domain is set at construction because each account clone
     * will recalculate its domain separator based on their own address.
     */
    constructor() EIP712("MyAccountCustom", "1") {
        _disableInitializers();
    }

    /// @dev Set up the account (e.g. load public keys to storage).
    function initialize() public virtual initializer {
        // Custom initialization logic
    }

    /// @dev Receives a hash wrapped in an EIP-712 domain separator.
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        // Custom signing logic
    }
}
