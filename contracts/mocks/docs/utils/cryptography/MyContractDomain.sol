// contracts/MyContractDomain.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @dev Unsafe contract to demonstrate the use of EIP712 and ECDSA.
abstract contract MyContractDomain is EIP712 {
    function validateSignature(
        address mailTo,
        string memory mailContents,
        bytes memory signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(keccak256("Mail(address to,string contents)"), mailTo, keccak256(bytes(mailContents))))
        );
        return ECDSA.recover(digest, signature);
    }
}
