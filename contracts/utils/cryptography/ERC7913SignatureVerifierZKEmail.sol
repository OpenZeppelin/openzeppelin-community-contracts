// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";
import {ZKEmailUtils} from "./ZKEmailUtils.sol";

/**
 * @dev ERC-7913 signature verifier that supports ZKEmail accounts.
 *
 * This contract verifies signatures produced through ZKEmail's zero-knowledge
 * proofs which allows users to authenticate using their email addresses.
 *
 * The key decoding logic is customizable: users may override the {_decodeKey} function
 * to enforce restrictions or validation on the decoded values (e.g., requiring a specific
 * verifier, templateId, or registry). To remain compliant with ERC-7913's statelessness,
 * it is recommended to enforce such restrictions using immutable variables only.
 *
 * Example of overriding _decodeKey to enforce a specific verifier, registry, (or templateId):
 *
 * ```solidity
 *   function _decodeKey(bytes calldata key) internal view override returns (
 *       IDKIMRegistry registry,
 *       bytes32 accountSalt,
 *       IVerifier verifier,
 *       uint256 templateId
 *   ) {
 *       (registry, accountSalt, verifier, templateId) = super._decodeKey(key);
 *       require(verifier == _verifier, "Invalid verifier");
 *       require(registry == _registry, "Invalid registry");
 *       return (registry, accountSalt, verifier, templateId);
 *   }
 * ```
 */
abstract contract ERC7913SignatureVerifierZKEmail is IERC7913SignatureVerifier {
    using ZKEmailUtils for EmailAuthMsg;

    /**
     * @dev Verifies a zero-knowledge proof of an email signature validated by a {DKIMRegistry} contract.
     *
     * The key format is ABI-encoded (IDKIMRegistry, bytes32, IVerifier, uint256) where:
     *
     * * IDKIMRegistry: The registry contract that validates DKIM public key hashes
     * * bytes32: The account salt that uniquely identifies the user's email address
     * * IVerifier: The verifier contract instance for ZK proof verification.
     * * uint256: The template ID for the command
     *
     * See {_decodeKey} for the key encoding format.
     *
     * The signature is an ABI-encoded {ZKEmailUtils-EmailAuthMsg} struct containing
     * the command parameters, template ID, and proof details.
     *
     * Signature encoding:
     *
     * ```solidity
     * bytes memory signature = abi.encode(EmailAuthMsg({
     *     templateId: 1,
     *     commandParams: [hash],
     *     proof: {
     *         domainName: "example.com", // The domain name of the email sender
     *         publicKeyHash: bytes32(0x...), // Hash of the DKIM public key used to sign the email
     *         timestamp: block.timestamp, // When the email was sent
     *         maskedCommand: "Sign hash", // The command being executed, with sensitive data masked
     *         emailNullifier: bytes32(0x...), // Unique identifier for the email to prevent replay attacks
     *         accountSalt: bytes32(0x...), // Unique identifier derived from email and account code
     *         isCodeExist: true, // Whether the account code exists in the proof
     *         proof: bytes(0x...) // The zero-knowledge proof verifying the email's authenticity
     *     }
     * }));
     * ```
     */
    function verify(
        bytes calldata key,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override returns (bytes4) {
        (IDKIMRegistry registry_, bytes32 accountSalt_, IVerifier verifier_, uint256 templateId_) = abi.decode(
            key,
            (IDKIMRegistry, bytes32, IVerifier, uint256)
        );
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));

        return
            (abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash &&
                emailAuthMsg.templateId == templateId_ &&
                emailAuthMsg.proof.accountSalt == accountSalt_ &&
                emailAuthMsg.isValidZKEmail(registry_, verifier_) == ZKEmailUtils.EmailProofError.NoError)
                ? IERC7913SignatureVerifier.verify.selector
                : bytes4(0xffffffff);
    }

    /**
     * @dev Decodes the key into its components.
     *
     * ```solidity
     * bytes memory key = abi.encode(registry, accountSalt, verifier, templateId);
     * ```
     */
    function _decodeKey(
        bytes calldata key
    )
        internal
        view
        virtual
        returns (IDKIMRegistry registry, bytes32 accountSalt, IVerifier verifier, uint256 templateId)
    {
        return abi.decode(key, (IDKIMRegistry, bytes32, IVerifier, uint256));
    }
}
