// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/zk-jwt/src/interfaces/IVerifier.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/src/libraries/CommandUtils.sol";

/**
 * @dev Library for https://docs.zk.email[ZK JWT] validation utilities.
 *
 * ZK JWT is a protocol that enables JWT-based authentication and authorization for smart contracts
 * using zero-knowledge proofs. It allows users to prove ownership of a JWT token without revealing
 * the token content or private keys. See https://datatracker.ietf.org/doc/html/rfc7519[RFC-7519] for
 * details on the JWT verification process.
 *
 * The validation process involves several key components:
 *
 * * A https://docs.zk.email/jwt-tx-builder/architecture[JWT Registry] verification mechanism to ensure
 * the JWT was issued from a valid issuer with valid public key. The registry validates the `kid|iss|azp` format
 * used in JWT verification (i.e. key id, issuer, and authorized party).
 * * A https://docs.zk.email/email-tx-builder/architecture/command-templates[command template] validation
 * mechanism to ensure the JWT command matches the expected format and parameters.
 * * A https://docs.zk.email/jwt-tx-builder/architecture[zero-knowledge proof] verification mechanism to ensure
 * the JWT was actually issued and received without revealing its contents through RSA signature validation
 * and selective claim disclosure.
 *
 * NOTE: This library adapts the email authentication infrastructure for JWT verification,
 * reusing the EmailProof structure which contains JWT-specific data encoded in the domainName field
 * as "kid|iss|azp" format.
 */
library ZKJWTUtils {
    using CommandUtils for bytes[];
    using Bytes for bytes;
    using Strings for string;

    /// @dev Enumeration of possible JWT proof validation errors.
    enum JWTProofError {
        NoError,
        JWTPublicKeyHash, // The JWT public key hash verification fails
        MaskedCommandLength, // The masked command length exceeds the maximum
        SkippedCommandPrefixSize, // The skipped command prefix size is invalid
        MismatchedCommand, // The command does not match the proof command
        JWTProof // The JWT proof verification fails
    }

    /// @dev Enumeration of possible string cases used to compare the command with the expected proven command.
    enum Case {
        CHECKSUM, // Computes a checksum of the command.
        LOWERCASE, // Converts the command to hex lowercase.
        UPPERCASE, // Converts the command to hex uppercase.
        ANY
    }

    /// @dev Validates a ZK JWT proof with default "signHash" command template.
    function isValidZKJWT(
        EmailProof memory jwtProof,
        IDKIMRegistry jwtRegistry,
        IVerifier verifier
    ) internal returns (JWTProofError) {
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = CommandUtils.UINT_MATCHER; // UINT_MATCHER is always lowercase
        return isValidZKJWT(jwtProof, jwtRegistry, verifier, signHashTemplate, Case.LOWERCASE);
    }

    /**
     * @dev Validates a ZK JWT proof against a command template.
     *
     * This function takes a JWT proof, a JWT registry contract, and a verifier contract
     * as inputs. It performs several validation checks and returns a {JWTProofError} indicating the result.
     * Returns {JWTProofError.NoError} if all validations pass, or a specific {JWTProofError} indicating
     * which validation check failed.
     *
     * NOTE: Attempts to validate the command for all possible string {Case} values.
     */
    function isValidZKJWT(
        EmailProof memory jwtProof,
        IDKIMRegistry jwtRegistry,
        IVerifier verifier,
        string[] memory template
    ) internal returns (JWTProofError) {
        return isValidZKJWT(jwtProof, jwtRegistry, verifier, template, Case.ANY);
    }

    /**
     * @dev Validates a ZK JWT proof against a template with a specific string {Case}.
     *
     * Useful for templates with Ethereum address matchers (i.e. `{ethAddr}`), which are case-sensitive
     * (e.g., `["someCommand", "{address}"]`).
     */
    function isValidZKJWT(
        EmailProof memory jwtProof,
        IDKIMRegistry jwtRegistry,
        IVerifier verifier,
        string[] memory template,
        Case stringCase
    ) internal returns (JWTProofError) {
        if (bytes(jwtProof.maskedCommand).length > verifier.getCommandBytes()) {
            return JWTProofError.MaskedCommandLength;
        } else if (!_commandMatch(jwtProof, template, stringCase)) {
            return JWTProofError.MismatchedCommand;
        } else if (!jwtRegistry.isDKIMPublicKeyHashValid(jwtProof.domainName, jwtProof.publicKeyHash)) {
            // Validate JWT public key and authorized party through registry
            // The domainName contains "kid|iss|azp" format for JWT validation
            return JWTProofError.JWTPublicKeyHash;
        }

        // Verify the zero-knowledge proof of JWT signature
        // TODO: Is `verifyEmailProof` supposed to be non-view?
        return verifier.verifyEmailProof(jwtProof) ? JWTProofError.NoError : JWTProofError.JWTProof;
    }

    /// @dev Compares the command in the JWT proof with the expected command template.
    function _commandMatch(
        EmailProof memory jwtProof,
        string[] memory template,
        Case stringCase
    ) private pure returns (bool) {
        // For JWT proofs, we extract command parameters from the maskedCommand
        // Since JWTs don't use the same command structure as emails, we adapt the validation
        string memory command = jwtProof.maskedCommand;

        // Convert template to expected command format
        bytes[] memory commandParams = new bytes[](template.length);
        for (uint256 i = 0; i < template.length; i++) {
            commandParams[i] = bytes(template[i]);
        }

        if (stringCase != Case.ANY) {
            return commandParams.computeExpectedCommand(template, uint8(stringCase)).equal(command);
        }

        return
            commandParams.computeExpectedCommand(template, uint8(Case.LOWERCASE)).equal(command) ||
            commandParams.computeExpectedCommand(template, uint8(Case.UPPERCASE)).equal(command) ||
            commandParams.computeExpectedCommand(template, uint8(Case.CHECKSUM)).equal(command);
    }
}
