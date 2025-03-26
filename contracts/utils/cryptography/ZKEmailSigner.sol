// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

abstract contract ZKEmailSigner is AbstractSigner {
    enum EmailProofError {
        NoError,
        CommandTemplate, // The template ID doesn't match
        DKIMPublicKeyHash, // The DKIM public key hash verification fails
        AccountSalt, // The account salt doesn't match
        MaskedCommandLength, // The masked command length exceeds the maximum
        SkippedCommandPrefixSize, // The skipped command prefix size is invalid
        Command, // The command format is invalid
        EmailProof // The email proof verification fails
    }

    error InvalidEmailProof(EmailProofError err);

    /// @dev Unique identifier for owner of this contract defined as a hash of an email address and an account code.
    function accountSalt() public view virtual returns (bytes32);

    /// @dev An instance of the DKIM registry contract.
    // solhint-disable-next-line func-name-mixedcase
    function DKIMRegistry() public view virtual returns (IDKIMRegistry);

    /// @dev An instance of the Verifier contract.
    function verifier() public view virtual returns (IVerifier);

    /// @dev The templateId of the sign hash command.
    function commandTemplate() public view virtual returns (uint256);

    /** @dev Authenticate the email sender and authorize the message in the email command.
     *
     * NOTE: This function only verifies the authenticity of the email and command, without
     * handling replay protection. The calling contract should implement its own mechanisms
     * to prevent replay attacks, similar to how nonces are used with ECDSA signatures.
     */
    function verifyEmail(EmailAuthMsg memory emailAuthMsg) public view virtual {
        (bool verified, EmailProofError err) = _verifyEmail(emailAuthMsg);
        if (!verified) revert InvalidEmailProof(err);
    }

    /// @inheritdoc AbstractSigner
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        // signature is a serialized EmailAuthMsg
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));
        (bool verified, ) = _verifyEmail(emailAuthMsg);
        return verified && abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash;
    }

    /// @dev Internal function to verify an email authenticated message that doesn't revert and returns a boolean and the error instead.
    function _verifyEmail(EmailAuthMsg memory emailAuthMsg) internal view virtual returns (bool, EmailProofError) {
        if (commandTemplate() != emailAuthMsg.templateId) return (false, EmailProofError.CommandTemplate);
        string[] memory signHashTemplate = new string[](2);
        signHashTemplate[0] = "signHash";
        signHashTemplate[1] = "{uint}";

        if (!DKIMRegistry().isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash))
            return (false, EmailProofError.DKIMPublicKeyHash);
        if (accountSalt() != emailAuthMsg.proof.accountSalt) return (false, EmailProofError.AccountSalt);
        if (bytes(emailAuthMsg.proof.maskedCommand).length > verifier().commandBytes())
            return (false, EmailProofError.MaskedCommandLength);
        if (emailAuthMsg.skippedCommandPrefix >= verifier().commandBytes())
            return (false, EmailProofError.SkippedCommandPrefixSize);

        // Construct an expectedCommand from template and the values of emailAuthMsg.commandParams.
        string memory trimmedMaskedCommand = CommandUtils.removePrefix(
            emailAuthMsg.proof.maskedCommand,
            emailAuthMsg.skippedCommandPrefix
        );
        string memory expectedCommand = "";
        for (uint256 stringCase = 0; stringCase < 3; stringCase++) {
            expectedCommand = CommandUtils.computeExpectedCommand(
                emailAuthMsg.commandParams,
                signHashTemplate,
                stringCase
            );
            if (Strings.equal(expectedCommand, trimmedMaskedCommand)) {
                break;
            }
            if (stringCase == 2) {
                return (false, EmailProofError.Command);
            }
        }

        if (!verifier().verifyEmailProof(emailAuthMsg.proof)) return (false, EmailProofError.EmailProof);
        return (true, EmailProofError.NoError);
    }
}
