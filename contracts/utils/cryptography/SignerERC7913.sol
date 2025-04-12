// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {AbstractSigner} from "./AbstractSigner.sol";
import {ERC7913Utils} from "./ERC7913Utils.sol";

/**
 * @dev Implementation of {AbstractSigner} using
 * https://eips.ethereum.org/EIPS/eip-7913[ERC-7913] signature verification.
 *
 * For {Account} usage, a {_setSigner} function is provided to set the ERC-7913 formatted {signer}.
 * Doing so is easier for a factory, who is likely to use initializable clones of this contract.
 *
 * The signer is a `bytes` object that concatenates a verifier address and a key: `verifier || key`.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountERC7913 is Account, SignerERC7913, Initializable {
 *     constructor() EIP712("MyAccountERC7913", "1") {}
 *
 *     function initialize(bytes memory signer_) public initializer {
 *       _setSigner(signer_);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Failing to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */

abstract contract SignerERC7913 is AbstractSigner {
    bytes private _signer;

    /// @dev Sets the signer (i.e. `verifier || key`) with an ERC-7913 formatted signer.
    function _setSigner(bytes memory signer_) internal {
        _signer = signer_;
    }

    /// @dev Return the ERC-7913 signer (i.e. `verifier || key`).
    function signer() public view virtual returns (bytes memory) {
        return _signer;
    }

    /// @dev Verifies a signature using {ERC7913Utils.isValidSignatureNow} with {signer}, `hash` and `signature`.
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        return ERC7913Utils.isValidSignatureNow(signer(), hash, signature);
    }
}
