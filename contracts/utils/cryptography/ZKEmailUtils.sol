// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

library ZKEmailUtils {
    using Strings for string;

    enum EmailProofError {
        NoError,
        DKIMPublicKeyHash, // The DKIM public key hash verification fails
        MaskedCommandLength, // The masked command length exceeds the maximum
        SkippedCommandPrefixSize, // The skipped command prefix size is invalid
        Command, // The command format is invalid
        EmailProof // The email proof verification fails
    }

    function isValidZKEmail(
        EmailAuthMsg memory emailAuthMsg,
        IDKIMRegistry dkimregistry,
        IVerifier verifier
    ) internal view returns (bool, EmailProofError) {
        if (!dkimregistry.isDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash)) {
            return (false, EmailProofError.DKIMPublicKeyHash);
        } else if (bytes(emailAuthMsg.proof.maskedCommand).length > verifier.commandBytes()) {
            return (false, EmailProofError.MaskedCommandLength);
        } else if (emailAuthMsg.skippedCommandPrefix >= verifier.commandBytes()) {
            return (false, EmailProofError.SkippedCommandPrefixSize);
        } else {
            string[] memory signHashTemplate = new string[](2);
            signHashTemplate[0] = "signHash";
            signHashTemplate[1] = CommandUtils.UINT_MATCHER;

            // Construct an expectedCommand from template and the values of emailAuthMsg.commandParams.
            string memory trimmedMaskedCommand = CommandUtils.removePrefix(
                emailAuthMsg.proof.maskedCommand,
                emailAuthMsg.skippedCommandPrefix
            );
            for (uint256 stringCase = 0; stringCase < 2; stringCase++) {
                if (
                    CommandUtils.computeExpectedCommand(emailAuthMsg.commandParams, signHashTemplate, stringCase).equal(
                        trimmedMaskedCommand
                    )
                ) {
                    if (verifier.verifyEmailProof(emailAuthMsg.proof)) return (true, EmailProofError.NoError);
                    else return (false, EmailProofError.EmailProof);
                }
            }
            return (false, EmailProofError.Command);
        }
    }
}
