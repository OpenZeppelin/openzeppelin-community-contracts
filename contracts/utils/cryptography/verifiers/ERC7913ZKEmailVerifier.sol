// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC7913SignatureVerifier} from "@openzeppelin/contracts/interfaces/IERC7913.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {EmailProof} from "@zk-email/email-tx-builder/src/interfaces/IEmailTypes.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {ZKEmailUtils} from "../ZKEmailUtils.sol";

/**
 * @dev ERC-7913 signature verifier that supports ZKEmail accounts.
 *
 * This contract verifies signatures produced through ZKEmail's zero-knowledge
 * proofs which allows users to authenticate using their email addresses.
 *
 * The key decoding logic is customizable: users may override the {_decodeKey} function
 * to enforce restrictions or validation on the decoded values (e.g., requiring a specific
 * verifier or registry). To remain compliant with ERC-7913's statelessness,
 * it is recommended to enforce such restrictions using immutable variables only.
 *
 * Example of overriding _decodeKey to enforce a specific verifier, registry:
 *
 * ```solidity
 *   function _decodeKey(bytes calldata key) internal view override returns (
 *       IDKIMRegistry registry,
 *       bytes32 accountSalt,
 *       IGroth16Verifier verifier
 *   ) {
 *       (registry, accountSalt, verifier) = super._decodeKey(key);
 *       require(verifier == _verifier, "Invalid verifier");
 *       require(registry == _registry, "Invalid registry");
 *       return (registry, accountSalt, verifier);
 *   }
 * ```
 */
contract ERC7913ZKEmailVerifier is IERC7913SignatureVerifier {
    using ZKEmailUtils for EmailProof;

    /**
     * @dev Verifies a zero-knowledge proof of an email signature validated by a {DKIMRegistry} contract.
     *
     * The key format is ABI-encoded (IDKIMRegistry, bytes32, IGroth16Verifier) where:
     *
     * * IDKIMRegistry: The registry contract that validates DKIM public key hashes
     * * bytes32: The account salt that uniquely identifies the user's email address
     * * IGroth16Verifier: The verifier contract instance for ZK proof verification.
     *
     * See {_decodeKey} for the key encoding format.
     *
     * The signature is an ABI-encoded {EmailProof} struct containing
     * the proof details.
     *
     * Signature encoding:
     *
     * ```solidity
     * bytes memory signature = abi.encode(EmailProof({
     *     domainName: "example.com", // The domain name of the email sender
     *     publicKeyHash: bytes32(0x...), // Hash of the DKIM public key used to sign the email
     *     timestamp: block.timestamp, // When the email was sent
     *     maskedCommand: "signHash 12345...", // The command being executed, with sensitive data masked
     *     emailNullifier: bytes32(0x...), // Unique identifier for the email to prevent replay attacks
     *     accountSalt: bytes32(0x...), // Unique identifier derived from email and account code
     *     isCodeExist: true, // Whether the account code exists in the proof
     *     proof: bytes(0x...) // The zero-knowledge proof verifying the email's authenticity
     * }));
     * ```
     */
    function verify(
        bytes calldata key,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override returns (bytes4) {
        (IDKIMRegistry registry_, bytes32 accountSalt_, IGroth16Verifier verifier_) = _decodeKey(key);
        (bool decodeSuccess, EmailProof calldata emailProof) = ZKEmailUtils.tryDecodeEmailProof(signature);

        return
            (decodeSuccess &&
                emailProof.accountSalt == accountSalt_ &&
                emailProof.isValidZKEmail(registry_, verifier_, hash) == ZKEmailUtils.EmailProofError.NoError)
                ? IERC7913SignatureVerifier.verify.selector
                : bytes4(0xffffffff);
    }

    /**
     * @dev Decodes the key into its components.
     *
     * ```solidity
     * bytes memory key = abi.encode(registry, accountSalt, verifier);
     * ```
     */
    function _decodeKey(
        bytes calldata key
    ) internal view virtual returns (IDKIMRegistry registry, bytes32 accountSalt, IGroth16Verifier verifier) {
        return abi.decode(key, (IDKIMRegistry, bytes32, IGroth16Verifier));
    }
}
