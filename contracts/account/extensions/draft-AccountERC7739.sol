// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {ERC7739Signer} from "../../utils/cryptography/draft-ERC7739Signer.sol";
import {AccountBase} from "../draft-AccountBase.sol";

/**
 * @dev An ERC-4337 account implementation that validates domain-specific signatures following ERC-7739.
 */
abstract contract AccountERC7739 is ERC165, IERC5267, ERC7739Signer, AccountBase {
    /**
     * @dev Internal version of {validateUserOp} that relies on {_validateSignature}.
     *
     * NOTE: To override the signature functionality, try overriding {_validateSignature} instead.
     */
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view virtual override returns (uint256) {
        return
            _isValidSignature(userOpHash, userOp.signature)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED;
    }
}
