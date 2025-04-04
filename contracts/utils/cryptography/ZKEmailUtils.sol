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
        InvalidCommand, // The command format is invalid
        EmailProof // The email proof verification fails
    }

    /**
     * @dev Variant of {isValidZKEmail} that validates the `["signHash", "{uint}"]` command template.
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier
    ) internal view returns (EmailProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER;

        return isValidZKEmail(emailAuthMsg, dkimregistry, verifier);
    }

    /**
     * @dev Validates a ZK-Email authentication message.
     *
     * Requirements:
     *
     * - The DKIM public key hash must be valid according to the registry
     * - The masked command length must not exceed the verifier's limit
     * - The skipped command prefix size must be valid
     * - The command format and parameters must be valid
     * - The email proof must be verified by the verifier
     *
     * This function takes an email authentication message, a DKIM registry contract, and a verifier contract
     * as inputs. It performs several validation checks and returns a tuple containing a boolean success flag
     * and an {EmailProofError} if validation failed. The function will return true with {EmailProofError.NoError}
     * if all validations pass, or false with a specific {EmailProofError} indicating which validation check failed.
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier,
        string[] memory template
    ) internal view returns (EmailProofError) {
        if (!dkimregistry.isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash)) {
            return EmailProofError.DKIMPublicKeyHash;
        } else if (bytes(emailAuthMsg.proof.maskedCommand).length > verifier.commandBytes()) {
            return EmailProofError.MaskedCommandLength;
        } else if (emailAuthMsg.skippedCommandPrefix >= verifier.commandBytes()) {
            return EmailProofError.SkippedCommandPrefixSize;
        } else if (
            !CommandUtils.computeExpectedCommand(emailAuthMsg.commandParams, template, 0).equal(
                CommandUtils.removePrefix(emailAuthMsg.proof.maskedCommand, emailAuthMsg.skippedCommandPrefix)
            )
        ) {
            return EmailProofError.InvalidCommand;
        } else if (verifier.verifyEmailProof(emailAuthMsg.proof)) {
            return EmailProofError.NoError;
        } else {
            return EmailProofError.EmailProof;
        }
    }
}
