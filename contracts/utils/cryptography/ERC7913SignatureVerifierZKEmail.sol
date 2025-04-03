// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";
import {ZKEmailUtils} from "./ZKEmailUtils.sol";

/**
 * @dev ERC-7913 signature verifier that support ZKEmail accounts.
 */
contract ERC7913SignatureVerifierZKEmail is IERC7913SignatureVerifier {
    using ZKEmailUtils for EmailAuthMsg;

    IVerifier public immutable verifier;
    uint256 public immutable commandTemplate;

    constructor(IVerifier _verifier, uint256 _commandTemplate) {
        verifier = _verifier;
        commandTemplate = _commandTemplate;
    }

    /// @inheritdoc IERC7913SignatureVerifier
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) public view virtual returns (bytes4) {
        (IDKIMRegistry registry, bytes32 accountSalt) = abi.decode(key, (IDKIMRegistry, bytes32));
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));
        if (
            bytes32(emailAuthMsg.commandParams[0]) == hash &&
            emailAuthMsg.templateId == commandTemplate &&
            emailAuthMsg.proof.accountSalt == accountSalt
        ) {
            (bool verified, ) = emailAuthMsg.isValidZKEmail(registry, verifier);
            if (verified) {
                return IERC7913SignatureVerifier.verify.selector;
            }
        }
        return 0xffffffff;
    }
}
