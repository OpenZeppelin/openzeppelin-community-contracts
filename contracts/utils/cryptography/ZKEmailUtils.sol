// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {EmailProof} from "@zk-email/email-tx-builder/src/interfaces/IEmailTypes.sol";
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
        EmailProof memory emailProof,
        IDKIMRegistry dkimregistry,
        IGroth16Verifier groth16Verifier,
        bytes32 hash
    ) internal view returns (EmailProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER; // UINT_MATCHER is always lowercase
        bytes[] memory signHashParams = new bytes[](1);
        signHashParams[0] = abi.encode(hash);
        return
            isValidZKEmail(emailProof, dkimregistry, groth16Verifier, signHashTemplate, signHashParams, Case.LOWERCASE);
    }

    /**
     * @dev Validates a ZKEmail proof against a command template.
     *
     * This function takes an email proof, a DKIM registry contract, and a verifier contract
     * as inputs. It performs several validation checks and returns an {EmailProofError} indicating the result.
     * Returns {EmailProofError.NoError} if all validations pass, or a specific {EmailProofError} indicating
     * which validation check failed.
     *
     * NOTE: Attempts to validate the command for all possible string {Case} values.
     */
    function isValidZKEmail(
        EmailProof memory emailProof,
        IDKIMRegistry dkimregistry,
        IGroth16Verifier groth16Verifier,
        string[] memory template,
        bytes[] memory templateParams
    ) internal view returns (EmailProofError) {
        return isValidZKEmail(emailProof, dkimregistry, groth16Verifier, template, templateParams, Case.ANY);
    }

    /**
     * @dev Variant of {isValidZKEmail} that validates a template with a specific string {Case}.
     *
     * Useful for templates with Ethereum address matchers (i.e. `{ethAddr}`), which are case-sensitive (e.g., `["someCommand", "{address}"]`).
     */
    function isValidZKEmail(
        EmailProof memory emailProof,
        IDKIMRegistry dkimregistry,
        IGroth16Verifier groth16Verifier,
        string[] memory template,
        bytes[] memory templateParams,
        Case stringCase
    ) internal view returns (EmailProofError) {
        if (bytes(emailProof.maskedCommand).length > COMMAND_BYTES) {
            return EmailProofError.MaskedCommandLength;
        } else if (!_commandMatch(emailProof, template, templateParams, stringCase)) {
            return EmailProofError.MismatchedCommand;
        } else if (!dkimregistry.isDKIMPublicKeyHashValid(emailProof.domainName, emailProof.publicKeyHash)) {
            return EmailProofError.DKIMPublicKeyHash;
        }

        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) = abi.decode(
            emailProof.proof,
            (uint256[2], uint256[2][2], uint256[2])
        );
        if (!_isValidFieldPoint(pA, pB, pC)) {
            return EmailProofError.InvalidFieldPoint;
        }

        return
            groth16Verifier.verifyProof(pA, pB, pC, toPubSignals(emailProof))
                ? EmailProofError.NoError
                : EmailProofError.EmailProof;
    }

    /**
     * @dev Verifies that calldata bytes (`input`) represents a valid `EmailProof` object. If encoding is valid,
     * returns true and the calldata view at the object. Otherwise, returns false and an invalid calldata object.
     *
     * NOTE: The returned `emailProof` object should not be accessed if `success` is false. Trying to access the data may
     * cause revert/panic.
     */
    function tryDecodeEmailProof(
        bytes calldata input
    ) internal pure returns (bool success, EmailProof calldata emailProof) {
        assembly ("memory-safe") {
            emailProof := input.offset
        }

        // Minimum length to hold 8 objects (32 bytes each)
        if (input.length < 0x100) return (false, emailProof);

        // Get offset of non-value-type elements relative to the input buffer
        uint256 domainNameOffset = uint256(bytes32(input[0x00:]));
        uint256 maskedCommandOffset = uint256(bytes32(input[0x60:]));
        uint256 proofOffset = uint256(bytes32(input[0xe0:]));

        // The elements length (at the offset) should be 32 bytes long. We check that this is within the
        // buffer bounds. Since we know input.length is at least 32, we can subtract with no overflow risk.
        if (
            input.length - 0x20 < domainNameOffset ||
            input.length - 0x20 < maskedCommandOffset ||
            input.length - 0x20 < proofOffset
        ) return (false, emailProof);

        // Get the lengths. offset + 32 is bounded by input.length so it does not overflow.
        uint256 domainNameLength = uint256(bytes32(input[domainNameOffset:]));
        uint256 maskedCommandLength = uint256(bytes32(input[maskedCommandOffset:]));
        uint256 proofLength = uint256(bytes32(input[proofOffset:]));

        // Check that the input buffer is long enough to store the non-value-type elements
        // Since we know input.length is at least xxxOffset + 32, we can subtract with no overflow risk.
        if (
            input.length - domainNameOffset - 0x20 < domainNameLength ||
            input.length - maskedCommandOffset - 0x20 < maskedCommandLength ||
            input.length - proofOffset - 0x20 < proofLength
        ) return (false, emailProof);

        return (true, emailProof);
    }

    /// @dev Compares the command in the email proof with the expected command template.
    function _commandMatch(
        EmailProof memory proof,
        string[] memory template,
        bytes[] memory templateParams,
        Case stringCase
    ) private pure returns (bool) {
        if (stringCase != Case.ANY)
            return templateParams.computeExpectedCommand(template, uint8(stringCase)).equal(proof.maskedCommand);

        return
            templateParams.computeExpectedCommand(template, uint8(Case.LOWERCASE)).equal(proof.maskedCommand) ||
            templateParams.computeExpectedCommand(template, uint8(Case.UPPERCASE)).equal(proof.maskedCommand) ||
            templateParams.computeExpectedCommand(template, uint8(Case.CHECKSUM)).equal(proof.maskedCommand);
    }

    /**
     * @dev Builds the expected public signals array for the Groth16 verifier from the given EmailProof.
     *
     * Packs the domain, public key hash, email nullifier, timestamp, masked command, account salt, and isCodeExist fields
     * into a uint256 array in the order expected by the verifier circuit.
     */
    function toPubSignals(
        EmailProof memory proof
    ) internal pure returns (uint256[DOMAIN_FIELDS + COMMAND_FIELDS + 5] memory pubSignals) {
        uint256[] memory stringFields;

        stringFields = _packBytes2Fields(bytes(proof.domainName), DOMAIN_BYTES);
        for (uint256 i = 0; i < DOMAIN_FIELDS; i++) {
            pubSignals[i] = stringFields[i];
        }

        pubSignals[DOMAIN_FIELDS] = uint256(proof.publicKeyHash);
        pubSignals[DOMAIN_FIELDS + 1] = uint256(proof.emailNullifier);
        pubSignals[DOMAIN_FIELDS + 2] = uint256(proof.timestamp);

        stringFields = _packBytes2Fields(bytes(proof.maskedCommand), COMMAND_BYTES);
        for (uint256 i = 0; i < COMMAND_FIELDS; i++) {
            pubSignals[DOMAIN_FIELDS + 3 + i] = stringFields[i];
        }

        pubSignals[DOMAIN_FIELDS + 3 + COMMAND_FIELDS] = uint256(proof.accountSalt);
        pubSignals[DOMAIN_FIELDS + 3 + COMMAND_FIELDS + 1] = proof.isCodeExist ? 1 : 0;

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
        uint256[] memory fields = new uint256[](numFields);
        uint256 idx;
        uint256 byteVal;
        for (uint256 i; i < numFields; i++) {
            for (uint256 j; j < 31; j++) {
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

    /// @dev Checks if the field points are valid in the range of [0, Q).
    function _isValidFieldPoint(
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) private pure returns (bool) {
        return
            pA[0] < Q &&
            pA[1] < Q &&
            pB[0][0] < Q &&
            pB[0][1] < Q &&
            pB[1][0] < Q &&
            pB[1][1] < Q &&
            pC[0] < Q &&
            pC[1] < Q;
    }
}
