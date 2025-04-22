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
 * This verifier validates signatures produced through ZKEmail's zero-knowledge
 * proofs which allows users to authenticate using their email addresses.
 */
abstract contract ERC7913SignatureVerifierZKEmail is IERC7913SignatureVerifier {
    using ZKEmailUtils for EmailAuthMsg;

    IVerifier private immutable _verifier;
    uint256 private immutable _templateId;

    constructor(IVerifier verifier_, uint256 templateId_) {
        _verifier = verifier_;
        _templateId = templateId_;
    }

    /// @dev An instance of the Verifier contract.
    /// See https://docs.zk.email/architecture/zk-proofs#how-zk-email-uses-zero-knowledge-proofs[ZK Proofs].
    function verifier() public view virtual returns (IVerifier) {
        return _verifier;
    }

    /// @dev The command template of the sign hash command.
    function templateId() public view virtual returns (uint256) {
        return _templateId;
    }

    /**
     * @dev Verifies a zero-knowledge proof of an email signature validated by a {DKIMRegistry} contract.
     *
     * The key format is ABI-encoded (IDKIMRegistry, bytes32) where:
     * - IDKIMRegistry: The registry contract that validates DKIM public key hashes
     * - bytes32: The account salt that uniquely identifies the user's email address
     *
     * The signature is an ABI-encoded {ZKEmailUtils-EmailAuthMsg} struct containing
     * the command parameters, template ID, and proof details.
     *
     * Key encoding:
     *
     * ```solidity
     * bytes memory key = abi.encode(registry, accountSalt);
     * ```
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
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) public view virtual returns (bytes4) {
        (IDKIMRegistry registry, bytes32 accountSalt) = abi.decode(key, (IDKIMRegistry, bytes32));
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));

        return
            (abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash &&
                emailAuthMsg.templateId == templateId() &&
                emailAuthMsg.proof.accountSalt == accountSalt &&
                emailAuthMsg.isValidZKEmail(registry, verifier()) == ZKEmailUtils.EmailProofError.NoError)
                ? IERC7913SignatureVerifier.verify.selector
                : bytes4(0xffffffff);
    }
}
