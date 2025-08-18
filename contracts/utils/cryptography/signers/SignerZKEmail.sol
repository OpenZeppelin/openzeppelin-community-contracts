// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {EmailProof} from "@zk-email/email-tx-builder/src/interfaces/IVerifier.sol";
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
 * * {verifier} - An instance of the Groth16Verifier contract for zero-knowledge proof validation.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountZKEmail is Account, SignerZKEmail, Initializable {
 *   function initialize(
 *       bytes32 accountSalt,
 *       IDKIMRegistry registry,
 *       IGroth16Verifier groth16Verifier
 *   ) public initializer {
 *       // Will revert if the signer is already initialized
 *       _setAccountSalt(accountSalt);
 *       _setDKIMRegistry(registry);
 *       _setVerifier(groth16Verifier);
 *   }
 * }
 * ```
 *
 * IMPORTANT: Failing to call {_setAccountSalt}, {_setDKIMRegistry}, and {_setVerifier}
 * either during construction (if used standalone) or during initialization (if used as a clone) may
 * leave the signer either front-runnable or unusable.
 */
abstract contract SignerZKEmail is AbstractSigner {
    using ZKEmailUtils for EmailProof;

    bytes32 private _accountSalt;
    IDKIMRegistry private _registry;
    IGroth16Verifier private _groth16Verifier;

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
     * @dev An instance of the Groth16Verifier contract.
     * See https://docs.zk.email/architecture/zk-proofs#how-zk-email-uses-zero-knowledge-proofs[ZK Proofs].
     */
    function verifier() public view virtual returns (IGroth16Verifier) {
        return _groth16Verifier;
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
    function _setVerifier(IGroth16Verifier verifier_) internal virtual {
        _groth16Verifier = verifier_;
    }

    /**
     * @dev See {AbstractSigner-_rawSignatureValidation}. Validates a raw signature by:
     *
     * 1. Decoding the email proof from the signature
     * 2. Validating the account salt matches
     * 3. Verifying the email proof using ZKEmail utilities
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bool decodeSuccess, EmailProof calldata emailProof) = ZKEmailUtils.tryDecodeEmailProof(signature);

        return
            decodeSuccess &&
            emailProof.accountSalt == accountSalt() &&
            emailProof.isValidZKEmail(DKIMRegistry(), verifier(), hash) == ZKEmailUtils.EmailProofError.NoError;
    }
}
