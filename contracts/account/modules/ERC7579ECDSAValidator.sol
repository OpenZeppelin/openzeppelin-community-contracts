// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC7579Validator} from "./ERC7579Validator.sol";

/**
 * @dev {ERC7579Validator} for {ECDSA} signatures.
 */
abstract contract ERC7579ECDSAValidator is ERC7579Validator {
    mapping(address sender => address signer) private _associatedSigners;

    /// @dev Emitted when an account is associated with an ECDSA signer.
    event ECDSASignerAssociated(address indexed account, address indexed signer);

    /// @dev Return the account's signer address for the given account.
    function signer(address account) public view virtual returns (address) {
        return _associatedSigners[account];
    }

    /**
     * @dev Associates an account with an ECDSA signer.
     *
     * The `data` is expected to be an `abi.encodePacked(signerAddr)`.
     *
     * NOTE: The validity of `data` is not checked.
     */
    function onInstall(bytes calldata data) public virtual {
        _setSigner(msg.sender, address(bytes20(data[0:20])));
    }

    /// @dev Disassociates an account from an ECDSA signer.
    function onUninstall(bytes calldata) public virtual {
        _setSigner(msg.sender, address(0));
    }

    /// @dev Sets the ECDSA address in the account's associated storage.
    function _setSigner(address account, address signerAddr) internal {
        _associatedSigners[account] = signerAddr;
        emit ECDSASignerAssociated(account, signerAddr);
    }

    /// @dev Validates the signature using the account's signer.
    function _isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return signer(sender) == recovered && err == ECDSA.RecoverError.NoError;
    }
}
