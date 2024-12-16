// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccountCore} from "../draft-AccountCore.sol";

abstract contract AccountSignerERC7702 is AccountCore {
    /**
     * @dev Validates the signature using the account's address.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return address(this) == recovered && err == ECDSA.RecoverError.NoError;
    }
}
