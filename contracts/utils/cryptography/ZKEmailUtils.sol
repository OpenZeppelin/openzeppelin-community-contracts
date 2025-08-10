// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/src/interfaces/IEmailTypes.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/src/libraries/CommandUtils.sol";

/**
 * @dev Library for https://docs.zk.email[ZKEmail] Groth16 proof validation utilities.
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
 * mechanism to ensure the email was actually sent and received without revealing its contents. Defined by an `IGroth16Verifier` interface.
 */
library ZKEmailUtils {
    using CommandUtils for bytes[];
    using Bytes for bytes;
    using Strings for string;

    uint256 internal constant DOMAIN_FIELDS = 9;
    uint256 internal constant DOMAIN_BYTES = 255;
    uint256 internal constant COMMAND_FIELDS = 20;
    uint256 internal constant COMMAND_BYTES = 605;

    /// @dev The base field size for BN254 elliptic curve used in Groth16 proofs.
    uint256 internal constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @dev Enumeration of possible email proof validation errors.
    enum EmailProofError {
        NoError,
        DKIMPublicKeyHash, // The DKIM public key hash verification fails
        MaskedCommandLength, // The masked command length exceeds the maximum
        SkippedCommandPrefixSize, // The skipped command prefix size is invalid
        MismatchedCommand, // The command does not match the proof command
        InvalidFieldPoint, // The Groth16 field point is invalid
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
        IGroth16Verifier groth16Verifier
    ) internal view returns (EmailProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER; // UINT_MATCHER is always lowercase
        return isValidZKEmail(emailAuthMsg, dkimregistry, groth16Verifier, signHashTemplate, Case.LOWERCASE);
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
        IGroth16Verifier groth16Verifier,
        string[] memory template
    ) internal view returns (EmailProofError) {
        return isValidZKEmail(emailAuthMsg, dkimregistry, groth16Verifier, template, Case.ANY);
    }

    /**
     * @dev Variant of {isValidZKEmail} that validates a template with a specific string {Case}.
     *
     * Useful for templates with Ethereum address matchers (i.e. `{ethAddr}`), which are case-sensitive (e.g., `["someCommand", "{address}"]`).
     */
    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IGroth16Verifier groth16Verifier,
        string[] memory template,
        Case stringCase
    ) internal view returns (EmailProofError) {
        if (emailAuthMsg.skippedCommandPrefix >= COMMAND_BYTES) {
            return EmailProofError.SkippedCommandPrefixSize;
        } else if (bytes(emailAuthMsg.proof.maskedCommand).length > COMMAND_BYTES) {
            return EmailProofError.MaskedCommandLength;
        } else if (!_commandMatch(emailAuthMsg, template, stringCase)) {
            return EmailProofError.MismatchedCommand;
        } else if (
            !dkimregistry.isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash)
        ) {
            return EmailProofError.DKIMPublicKeyHash;
        }
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) = abi.decode(
            emailAuthMsg.proof.proof,
            (uint256[2], uint256[2][2], uint256[2])
        );

        uint256 q = Q - 1; // upper bound of the field elements
        if (
            pA[0] > q ||
            pA[1] > q ||
            pB[0][0] > q ||
            pB[0][1] > q ||
            pB[1][0] > q ||
            pB[1][1] > q ||
            pC[0] > q ||
            pC[1] > q
        ) return EmailProofError.InvalidFieldPoint;

        return
            groth16Verifier.verifyProof(pA, pB, pC, toPubSignals(emailAuthMsg))
                ? EmailProofError.NoError
                : EmailProofError.EmailProof;
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

    /**
     * @dev Builds the expected public signals array for the Groth16 verifier from the given EmailAuthMsg.
     *
     * Packs the domain, public key hash, email nullifier, timestamp, masked command, account salt, and isCodeExist fields
     * into a uint256 array in the order expected by the verifier circuit.
     */
    function toPubSignals(
        EmailAuthMsg memory emailAuthMsg
    ) internal pure returns (uint256[DOMAIN_FIELDS + COMMAND_FIELDS + 5] memory pubSignals) {
        uint256[] memory stringFields;

        stringFields = _packBytes2Fields(bytes(emailAuthMsg.proof.domainName), DOMAIN_BYTES);
        for (uint256 i = 0; i < DOMAIN_FIELDS; i++) {
            pubSignals[i] = stringFields[i];
        }

        pubSignals[DOMAIN_FIELDS] = uint256(emailAuthMsg.proof.publicKeyHash);
        pubSignals[DOMAIN_FIELDS + 1] = uint256(emailAuthMsg.proof.emailNullifier);
        pubSignals[DOMAIN_FIELDS + 2] = uint256(emailAuthMsg.proof.timestamp);

        stringFields = _packBytes2Fields(bytes(emailAuthMsg.proof.maskedCommand), COMMAND_BYTES);
        for (uint256 i = 0; i < COMMAND_FIELDS; i++) {
            pubSignals[DOMAIN_FIELDS + 3 + i] = stringFields[i];
        }

        pubSignals[DOMAIN_FIELDS + 3 + COMMAND_FIELDS] = uint256(emailAuthMsg.proof.accountSalt);
        pubSignals[DOMAIN_FIELDS + 3 + COMMAND_FIELDS + 1] = emailAuthMsg.proof.isCodeExist ? 1 : 0;

        return pubSignals;
    }

    /**
     * @dev Packs a bytes array into an array of uint256 fields, each field representing up to 31 bytes.
     * If the input is shorter than the padded size, the remaining bytes are zero-padded.
     */
    function _packBytes2Fields(bytes memory _bytes, uint256 _paddedSize) private pure returns (uint256[] memory) {
        uint256 remain = _paddedSize % 31;
        uint256 numFields = (_paddedSize - remain) / 31;
        if (remain > 0) {
            numFields += 1;
        }
        uint256[] memory fields = new uint[](numFields);
        uint256 idx = 0;
        uint256 byteVal = 0;
        for (uint256 i = 0; i < numFields; i++) {
            for (uint256 j = 0; j < 31; j++) {
                idx = i * 31 + j;
                if (idx >= _paddedSize) {
                    break;
                }
                if (idx >= _bytes.length) {
                    byteVal = 0;
                } else {
                    byteVal = uint256(uint8(_bytes[idx]));
                }
                if (j == 0) {
                    fields[i] = byteVal;
                } else {
                    fields[i] += (byteVal << (8 * j));
                }
            }
        }
        return fields;
    }
}
