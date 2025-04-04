// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Library for https://docs.zk.email[ZKEmail] signature validation utilities.
 *
 * ZKEmail is a protocol that enables email-based authentication and authorization for smart contracts
 * using zero-knowledge proofs. It allows users to prove ownership of an email address without revealing
 * the email content or private keys.
 *
 * The validation process involves several key components:
 *
 * * A https://docs.zk.email/architecture/dkim-verification[DKIMRegistry] (DomainKeys Identified Mail) verification
 * mechanism to ensure the email was sent from a valid domain. Defined by an `IDKIMRegistry` interface.
 * * A https://docs.zk.email/email-tx-builder/architecture/command-templates[command template] validation
 * mechanism to ensure the email command matches the expected format and parameters.
 * * A https://docs.zk.email/architecture/zk-proofs#how-zk-email-uses-zero-knowledge-proofs[zero-knowledge proof] verification
 * mechanism to ensure the email was actually sent and received without revealing its contents. Defined by an `IVerifier` interface.
 */
library ZKEmailUtils {
    using Strings for string;

    /// @dev Enumeration of possible email proof validation errors.
    enum EmailProofError {
        NoError,
        DKIMPublicKeyHash, // The DKIM public key hash verification fails
        MaskedCommandLength, // The masked command length exceeds the maximum
        SkippedCommandPrefixSize, // The skipped command prefix size is invalid
        MismatchedCommand, // The command does not match the proof command
        EmailProof // The email proof verification fails
    }

    /// @dev Enumeration of possible string cases used to compare the command with the expected proven command.
    enum Case {
        LOWERCASE, // Converts the command to hex lowercase.
        UPPERCASE, // Converts the command to hex uppercase.
        CHECKSUM // Computes a checksum of the command.
    }

    /// @dev Variant of {isValidZKEmail} that validates the `["signHash", "{uint}"]` command template.
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier
    ) internal view returns (EmailProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER;

        // UINT_MATCHER is always lowercase
        return isValidZKEmail(emailAuthMsg, dkimregistry, verifier, signHashTemplate, Case.LOWERCASE);
    }

    /**
     * @dev Validates a ZKEmail authentication message.
     *
     * This function takes an email authentication message, a DKIM registry contract, and a verifier contract
     * as inputs. It performs several validation checks and returns a tuple containing a boolean success flag
     * and an {EmailProofError} if validation failed. See {validateDKIMAndCommandFormat} and {validateExpectedCommandAndProof}
     * for more details on the validation checks performed.
     *
     * NOTE: Attempts to validate the command for all possible string {Case} values.
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier,
        string[] memory template
    ) internal view returns (EmailProofError) {
        EmailProofError err = validateDKIMAndCommandFormat(emailAuthMsg, dkimregistry, verifier);
        if (err != EmailProofError.NoError) return err;
        for (uint256 i = 0; i < uint8(type(Case).max) && err != EmailProofError.NoError; i++) {
            err = validateExpectedCommandAndProof(emailAuthMsg, verifier, template, Case(i));
        }
        return err;
    }

    /// @dev Variant of {isValidZKEmail} that validates a template with a specific string {Case}.
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier,
        string[] memory template,
        Case stringCase
    ) internal view returns (EmailProofError) {
        EmailProofError err = validateDKIMAndCommandFormat(emailAuthMsg, dkimregistry, verifier);
        return
            err == EmailProofError.NoError
                ? validateExpectedCommandAndProof(emailAuthMsg, verifier, template, stringCase)
                : err;
    }

    /**
     * @dev Validates the email authentication message parameters.
     *
     * * Returns {EmailProofError.DKIMPublicKeyHash} if the DKIM public key hash is not valid according to the registry.
     * * Returns {EmailProofError.MaskedCommandLength} if the proof's `maskedCommand` exceeds the verifier's command bytes.
     * * Returns {EmailProofError.SkippedCommandPrefixSize} if the proof's `skippedCommandPrefix` exceeds the verifier's command bytes.
     */
    function validateDKIMAndCommandFormat(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier
    ) internal view returns (EmailProofError) {
        if (!dkimregistry.isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash)) {
            return EmailProofError.DKIMPublicKeyHash;
        } else if (bytes(emailAuthMsg.proof.maskedCommand).length > verifier.commandBytes()) {
            return EmailProofError.MaskedCommandLength;
        } else if (emailAuthMsg.skippedCommandPrefix >= verifier.commandBytes()) {
            return EmailProofError.SkippedCommandPrefixSize;
        }
        return EmailProofError.NoError;
    }

    /**
     * @dev Validates the command and proof of the email authentication message.
     *
     * * Returns {EmailProofError.MismatchedCommand} if the command does not match the proof's command with {stringCase}.
     * * Returns {EmailProofError.EmailProof} if the email proof is invalid.
     */
    function validateExpectedCommandAndProof(
        EmailAuthMsg memory emailAuthMsg,
        IVerifier verifier,
        string[] memory template,
        Case stringCase
    ) internal view returns (EmailProofError) {
        string memory expectedCommand = CommandUtils.computeExpectedCommand(
            emailAuthMsg.commandParams,
            template,
            uint8(stringCase)
        );
        if (!expectedCommand.equal(emailAuthMsg.proof.maskedCommand)) {
            return EmailProofError.MismatchedCommand;
        }
        return verifier.verifyEmailProof(emailAuthMsg.proof) ? EmailProofError.NoError : EmailProofError.EmailProof;
    }
}
