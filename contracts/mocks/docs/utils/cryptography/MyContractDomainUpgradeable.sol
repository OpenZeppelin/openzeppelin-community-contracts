// contracts/MyContractDomain.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @dev Unsafe contract to demonstrate the use of EIP712 and ECDSA.
abstract contract MyContractDomainUpgradeable is Initializable, EIP712Upgradeable {
    function __MyContractDomain_init() internal onlyInitializing {
    }

    function __MyContractDomain_init_unchained() internal onlyInitializing {
    }
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
