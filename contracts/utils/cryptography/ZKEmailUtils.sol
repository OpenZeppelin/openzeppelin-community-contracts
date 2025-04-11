// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";

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
    using CommandUtils for bytes[];
    using Bytes for bytes;
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
        CHECKSUM, // Computes a checksum of the command.
        LOWERCASE, // Converts the command to hex lowercase.
        UPPERCASE, // Converts the command to hex uppercase.
        ANY
    }

    /// @dev Variant of {isValidZKEmail} that validates the `["signHash", "{uint}"]` command template.
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier
    ) internal view returns (EmailProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER; // UINT_MATCHER is always lowercase
        return isValidZKEmail(emailAuthMsg, dkimregistry, verifier, signHashTemplate, Case.LOWERCASE);
    }

    /**
     * @dev Validates a ZKEmail authentication message.
     *
     * This function takes an email authentication message, a DKIM registry contract, and a verifier contract
     * as inputs. It performs several validation checks and returns a tuple containing a boolean success flag
     * and an {EmailProofError} if validation failed. Returns {EmailProofError.NoError} if all validations pass,
     * or false with a specific {EmailProofError} indicating which validation check failed.
     *
     * NOTE: Attempts to validate the command for all possible string {Case} values.
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier,
        string[] memory template
    ) internal view returns (EmailProofError) {
        return isValidZKEmail(emailAuthMsg, dkimregistry, verifier, template, Case.ANY);
    }

    /**
     * @dev Variant of {isValidZKEmail} that validates a template with a specific string {Case}.
     *
     * Useful for templates with Ethereum address matchers (i.e. `{ethAddr}`), which are case-sensitive (e.g., `["someCommand", "{address}"]`).
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier,
        string[] memory template,
        Case stringCase
    ) internal view returns (EmailProofError) {
        if (emailAuthMsg.skippedCommandPrefix >= verifier.commandBytes()) {
            return EmailProofError.SkippedCommandPrefixSize;
        } else if (bytes(emailAuthMsg.proof.maskedCommand).length > verifier.commandBytes()) {
            return EmailProofError.MaskedCommandLength;
        } else if (!_commandMatch(emailAuthMsg, template, stringCase)) {
            return EmailProofError.MismatchedCommand;
        } else if (
            !dkimregistry.isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash)
        ) {
            return EmailProofError.DKIMPublicKeyHash;
        } else {
            return verifier.verifyEmailProof(emailAuthMsg.proof) ? EmailProofError.NoError : EmailProofError.EmailProof;
        }
    }

    /// @dev Compares the command in the email authentication message with the expected command.
    function _commandMatch(
        EmailAuthMsg memory emailAuthMsg,
        string[] memory template,
        Case stringCase
    ) private pure returns (bool) {
        bytes[] memory commandParams = emailAuthMsg.commandParams; // Not a memory copy
        uint256 skippedCommandPrefix = emailAuthMsg.skippedCommandPrefix; // Not a memory copy
        string memory command = string(bytes(emailAuthMsg.proof.maskedCommand).slice(skippedCommandPrefix)); // Not a memory copy

        if (stringCase != Case.ANY)
            return commandParams.computeExpectedCommand(template, uint8(stringCase)).equal(command);
        return
            commandParams.computeExpectedCommand(template, uint8(Case.LOWERCASE)).equal(command) ||
            commandParams.computeExpectedCommand(template, uint8(Case.UPPERCASE)).equal(command) ||
            commandParams.computeExpectedCommand(template, uint8(Case.CHECKSUM)).equal(command);
    }
}
