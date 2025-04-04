// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {AbstractSigner} from "./AbstractSigner.sol";
import {ZKEmailUtils} from "./ZKEmailUtils.sol";

/**
 * @dev Implementation of {AbstractSigner} using https://docs.zk.email[ZKEmail] signatures.
 *
 * ZKEmail enables secure authentication and authorization through email messages, leveraging
 * DKIM signatures from a trusted {DKIMRegistry} and zero-knowledge proofs enabled by a {verifier}
 * contract that ensures email authenticity without revealing sensitive information. This contract
 * implements the core functionality for validating email-based signatures in smart contracts.
 *
 * Developers must set the following components during contract initialization:
 *
 * * {accountSalt} - A unique identifier derived from the user's email address and account code.
 * * {DKIMRegistry} - An instance of the DKIM registry contract for domain verification.
 * * {verifier} - An instance of the Verifier contract for zero-knowledge proof validation.
 * * {templateId} - The template ID of the sign hash command, defining the expected format.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountZKEmail is Account, SignerZKEmail, Initializable {
 *     constructor(bytes32 accountSalt, IDKIMRegistry registry, IVerifier verifier, uint256 templateId) {
 *       // Will revert if the signer is already initialized
 *       _setAccountSalt(accountSalt);
 *       _setDKIMRegistry(registry);
 *       _setVerifier(verifier);
 *       _setTemplateId(templateId);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_setAccountSalt}, {_setDKIMRegistry}, {_setVerifier} and {_setTemplateId}
 * either during construction (if used standalone) or during initialization (if used as a clone) may
 * leave the signer either front-runnable or unusable.
 */
abstract contract SignerZKEmail is AbstractSigner {
    using ZKEmailUtils for EmailAuthMsg;

    bytes32 private _accountSalt;
    IDKIMRegistry private _registry;
    IVerifier private _verifier;
    uint256 private _templateId;

    /// @dev Proof verification error.
    error InvalidEmailProof(ZKEmailUtils.EmailProofError err);

    /**
     * @dev Unique identifier for owner of this contract defined as a hash of an email address and an account code.
     *
     * An account code is a random integer in a finite scalar field of https://neuromancer.sk/std/bn/bn254[BN254] curve.
     * It is a private randomness to derive a CREATE2 salt of the user's Ethereum address
     * from the email address, i.e., userEtherAddr := CREATE2(hash(userEmailAddr, accountCode)).
     *
     * The account salt is used for:
     *
     * * User Identification: Links the email address to a specific Ethereum address securely and deterministically.
     * * Security: Provides a unique identifier that cannot be easily guessed or brute-forced, as it's derived
     *   from both the email address and a random account code.
     * * Deterministic Address Generation: Enables the creation of deterministic addresses based on email addresses,
     *   allowing users to recover their accounts using only their email.
     */
    function accountSalt() public view virtual returns (bytes32) {
        return _accountSalt;
    }

    /// @dev An instance of the DKIM registry contract.
    /// See https://docs.zk.email/architecture/dkim-verification[DKIM Verification].
    // solhint-disable-next-line func-name-mixedcase
    function DKIMRegistry() public view virtual returns (IDKIMRegistry) {
        return _registry;
    }

    /// @dev An instance of the Verifier contract.
    /// See https://docs.zk.email/architecture/zk-proofs#how-zk-email-uses-zero-knowledge-proofs[ZK Proofs].
    function verifier() public view virtual returns (IVerifier) {
        return _verifier;
    }

    /// @dev The command template of the sign hash command.
    function templateId() public view virtual returns (uint256) {
        return _templateId;
    }

    /// @dev Set the {accountSalt}.
    function _setAccountSalt(bytes32 accountSalt_) internal virtual {
        _accountSalt = accountSalt_;
    }

    /// @dev Set the {DKIMRegistry} contract address.
    function _setDKIMRegistry(IDKIMRegistry registry_) internal virtual {
        _registry = registry_;
    }

    /// @dev Set the {verifier} contract address.
    function _setVerifier(IVerifier verifier_) internal virtual {
        _verifier = verifier_;
    }

    /// @dev Set the command's {templateId}.
    function _setTemplateId(uint256 templateId_) internal virtual {
        _templateId = templateId_;
    }

    /**
     * @dev Authenticates the email sender and authorizes the message in the email command.
     *
     * NOTE: This function only verifies the authenticity of the email and command, without
     * handling replay protection. The calling contract should implement its own mechanisms
     * to prevent replay attacks, similar to how nonces are used with ECDSA signatures.
     */
    function verifyEmail(EmailAuthMsg memory emailAuthMsg) public view virtual {
        if (emailAuthMsg.templateId != templateId() || emailAuthMsg.proof.accountSalt != accountSalt()) {
            revert InvalidEmailProof(ZKEmailUtils.EmailProofError.EmailProof);
        }
        ZKEmailUtils.EmailProofError err = emailAuthMsg.isValidZKEmail(DKIMRegistry(), verifier());
        if (err != ZKEmailUtils.EmailProofError.NoError) revert InvalidEmailProof(err);
    }

    /**
     * @dev See {AbstractSigner-_rawSignatureValidation}. Validates a raw signature by:
     *
     * 1. Decoding the email authentication message from the signature
     * 2. Verifying the hash matches the command parameters
     * 3. Checking the template ID matches
     * 4. Validating the account salt
     * 5. Verifying the email proof
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));
        return (abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash &&
            emailAuthMsg.templateId == templateId() &&
            emailAuthMsg.proof.accountSalt == accountSalt() &&
            emailAuthMsg.isValidZKEmail(DKIMRegistry(), verifier()) == ZKEmailUtils.EmailProofError.NoError);
    }
}
