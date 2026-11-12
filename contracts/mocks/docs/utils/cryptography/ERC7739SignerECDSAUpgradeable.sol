// contracts/ERC7739ECDSA.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {ERC7739Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/signers/draft-ERC7739Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract ERC7739ECDSAUpgradeable is Initializable, ERC7739Upgradeable {
    address private _signer;

    function __ERC7739ECDSA_init(address signerAddr) internal onlyInitializing {
        __EIP712_init_unchained("ERC7739ECDSA", "1");
        __ERC7739ECDSA_init_unchained(signerAddr);
    }

    function __ERC7739ECDSA_init_unchained(address signerAddr) internal onlyInitializing {
        _signer = signerAddr;
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return _signer == recovered && err == ECDSA.RecoverError.NoError;
    }
}
