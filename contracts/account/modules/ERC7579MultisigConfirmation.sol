// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7579Multisig} from "./ERC7579Multisig.sol";

/**
 * @dev Extension of {ERC7579Multisig} that requires explicit confirmation signatures
 * from new signers when they are being added to the multisig.
 *
 * This module ensures that only willing participants can be added as signers to a
 * multisig by requiring each new signer to provide a valid signature confirming their
 * consent to be added. Each signer must sign an EIP-712 message to confirm their addition.
 *
 * TIP: Use this module to ensure that all guardians in a social recovery or multisig setup have
 * explicitly agreed to their roles.
 */
abstract contract ERC7579MultisigConfirmation is ERC7579Multisig, EIP712 {
    bytes32 private constant MULTISIG_CONFIRMATION =
        keccak256("MultisigConfirmation(address account,address module,uint256 deadline)");

    /// @dev Error thrown when a `signer`'s confirmation signature is invalid
    error ERC7579MultisigInvalidConfirmationSignature(bytes signer);

    /// @dev Error thrown when a confirmation signature has expired
    error ERC7579MultisigExpiredConfirmation(uint256 deadline);

    /// @dev Generates a hash that signers must sign to confirm their addition to the multisig of `account`.
    function _signableConfirmationHash(address account, uint256 deadline) internal view virtual returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MULTISIG_CONFIRMATION, account, address(this), deadline)));
    }

    /**
     * @dev Extends {ERC7579Multisig-_addSigners} _addSigners to require confirmation signatures
     * Each entry in newSigners must be ABI-encoded as:
     *
     * ```solidity
     * abi.encode(deadline,signer,signature); // uint256, bytes, bytes
     * ```
     *
     * * signer: The ERC-7913 signer to add
     * * signature: The signature from this signer confirming their addition
     *
     * The function verifies each signature before adding the signer. If any signature is invalid,
     * the function reverts with {ERC7579MultisigInvalidConfirmationSignature}.
     */
    function _addSigners(address account, bytes[] memory newSigners) internal virtual override {
        uint256 newSignersLength = newSigners.length;
        for (uint256 i = 0; i < newSignersLength; i++) {
            (uint256 deadline, bytes memory signer, bytes memory signature) = abi.decode(
                newSigners[i],
                (uint256, bytes, bytes)
            );
            require(deadline > block.timestamp, ERC7579MultisigExpiredConfirmation(deadline));
            require(
                SignatureChecker.isValidSignatureNow(signer, _signableConfirmationHash(account, deadline), signature),
                ERC7579MultisigInvalidConfirmationSignature(signer)
            );
            newSigners[i] = signer; // Replace the ABI-encoded value with the signer
        }
        super._addSigners(account, newSigners);
    }
}
