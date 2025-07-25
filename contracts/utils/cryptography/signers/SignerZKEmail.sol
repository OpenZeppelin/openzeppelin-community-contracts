// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier} from "@zk-email/email-tx-builder/src/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/src/interfaces/IEmailTypes.sol";
import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {ZKEmailUtils} from "../ZKEmailUtils.sol";

/**
 * @dev Implementation of {AbstractSigner} using https://docs.zk.email[ZKEmail] signatures.
 *
 * ZKEmail enables secure authentication and authorization through email messages, leveraging
 * DKIM signatures from a {DKIMRegistry} and zero-knowledge proofs enabled by a {verifier}
 * contract that ensures email authenticity without revealing sensitive information. The DKIM
 * registry is trusted to correctly update DKIM keys, but users can override this behaviour and
 * set their own keys. This contract implements the core functionality for validating email-based
 * signatures in smart contracts.
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
 *   function initialize(
 *       bytes32 accountSalt,
 *       IDKIMRegistry registry,
 *       IVerifier verifier,
 *       uint256 templateId
 *   ) public initializer {
 *       // Will revert if the signer is already initialized
 *       _setAccountSalt(accountSalt);
 *       _setDKIMRegistry(registry);
 *       _setVerifier(verifier);
 *       _setTemplateId(templateId);
 *   }
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
     * * Privacy: Enables email address privacy on-chain so long as the randomly generated account code is not revealed
     *   to an adversary.
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

    /**
     * @dev An instance of the Verifier contract.
     * See https://docs.zk.email/architecture/zk-proofs#how-zk-email-uses-zero-knowledge-proofs[ZK Proofs].
     */
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
        // Check if the signature is long enough to contain the EmailAuthMsg
        // The minimum length is 512 bytes (initial part + pointer offsets)
        // - `templateId` is a uint256 (32 bytes).
        // - `commandParams` is a dynamic array of bytes32 (32 bytes offset).
        // - `skippedCommandPrefixSize` is a uint256 (32 bytes).
        // - `proof` is a struct with the following fields (32 bytes offset):
        //   - `domainName` is a dynamic string (32 bytes offset).
        //   - `publicKeyHash` is a bytes32 (32 bytes).
        //   - `timestamp` is a uint256 (32 bytes).
        //   - `maskedCommand` is a dynamic string (32 bytes offset).
        //   - `emailNullifier` is a bytes32 (32 bytes).
        //   - `accountSalt` is a bytes32 (32 bytes).
        //   - `isCodeExist` is a boolean, so its length is 1 byte padded to 32 bytes.
        //   - `proof` is a dynamic bytes (32 bytes offset).
        // There are 128 bytes for the EmailAuthMsg type and 256 bytes for the proof.
        // Considering all dynamic elements are empty (i.e. `commandParams` = [], `domainName` = "", `maskedCommand` = "", `proof` = []),
        // then we have 128 bytes for the EmailAuthMsg type, 256 bytes for the proof and 4 * 32 for the length of the dynamic elements.
        // So the minimum length is 128 + 256 + 4 * 32 = 512 bytes.
        if (signature.length < 512) return false;
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));
        return (abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash &&
            emailAuthMsg.templateId == templateId() &&
            emailAuthMsg.proof.accountSalt == accountSalt() &&
            emailAuthMsg.isValidZKEmail(DKIMRegistry(), verifier()) == ZKEmailUtils.EmailProofError.NoError);
    }
}
