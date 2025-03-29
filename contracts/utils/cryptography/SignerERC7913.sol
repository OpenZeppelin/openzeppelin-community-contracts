// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AbstractSigner} from "./AbstractSigner.sol";
import {ERC7913Utils} from "./ERC7913Utils.sol";

/**
 * @dev Implementation of {AbstractSigner} that supports ERC-7913 signers.
 *
 * For {Account} usage, an {_setSigner} function is provided to set the ERC-7913 formated {signer}.
 * Doing so it's easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountERC7913 is Account, SignerERC7913, Initializable {
 *     constructor() EIP712("MyAccountERC7913", "1") {}
 *
 *     function initialize(bytes memory signer) public initializer {
 *       _setSigner(signer);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */

abstract contract SignerERC7913 is AbstractSigner {
    bytes private _signer;

    function _setSigner(bytes memory signer_) internal {
        _signer = signer_;
    }

    function signer() public view virtual returns (bytes memory) {
        return _signer;
    }

    /// @inheritdoc AbstractSigner
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        return ERC7913Utils.isValidSignatureNow(signer(), hash, signature);
    }
}
