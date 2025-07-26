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
    /// See https://docs.zk.email/jwt-tx-builder/architecture[ZK JWT Architecture] for validation flow details.
    enum JWTProofError {
        NoError,
        JWTPublicKeyHash, // The JWT public key hash verification fails
        MaskedCommandLength, // The masked command length exceeds the maximum allowed by the circuit
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
        IVerifier verifier,
        bytes32 hash
    ) internal view returns (JWTProofError) {
        string[] memory signHashTemplate = new string[](1);
        signHashTemplate[0] = CommandUtils.UINT_MATCHER;
        bytes[] memory signHashParams = new bytes[](1);
        signHashParams[0] = abi.encode(hash);
        return isValidZKJWT(jwtProof, jwtRegistry, verifier, signHashTemplate, signHashParams, Case.LOWERCASE); // UINT_MATCHER is always lowercase
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
        string[] memory template,
        bytes[] memory templateParams
    ) internal view returns (JWTProofError) {
        return isValidZKJWT(jwtProof, jwtRegistry, verifier, template, templateParams, Case.ANY);
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
        bytes[] memory templateParams,
        Case stringCase
    ) internal view returns (JWTProofError) {
        if (bytes(jwtProof.maskedCommand).length > verifier.getCommandBytes()) {
            return JWTProofError.MaskedCommandLength;
        } else if (!_commandMatch(jwtProof, template, templateParams, stringCase)) {
            return JWTProofError.MismatchedCommand;
        } else if (!jwtRegistry.isDKIMPublicKeyHashValid(jwtProof.domainName, jwtProof.publicKeyHash)) {
            // Validate JWT public key and authorized party through registry
            // The domainName contains "kid|iss|azp" format for JWT validation
            return JWTProofError.JWTPublicKeyHash;
        }

        // Verify the zero-knowledge proof of JWT signature
        return verifier.verifyEmailProof(jwtProof) ? JWTProofError.NoError : JWTProofError.JWTProof;
    }

    /// @dev Compares the command in the JWT proof with the expected command template.
    function _commandMatch(
        EmailProof memory jwtProof,
        string[] memory template,
        bytes[] memory templateParams,
        Case stringCase
    ) private pure returns (bool) {
        // Convert template to expected command format
        uint256 commandPrefixLength = bytes(jwtProof.maskedCommand).indexOf(bytes1(" "));
        string memory command = string(bytes(jwtProof.maskedCommand).slice(commandPrefixLength + 1));

        if (stringCase != Case.ANY)
            return templateParams.computeExpectedCommand(template, uint8(stringCase)).equal(command);
        return
            templateParams.computeExpectedCommand(template, uint8(Case.LOWERCASE)).equal(command) ||
            templateParams.computeExpectedCommand(template, uint8(Case.UPPERCASE)).equal(command) ||
            templateParams.computeExpectedCommand(template, uint8(Case.CHECKSUM)).equal(command);
    }
}
