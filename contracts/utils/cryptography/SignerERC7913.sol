// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AbstractSigner} from "./AbstractSigner.sol";
import {ERC7913Utils} from "./ERC7913Utils.sol";

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
