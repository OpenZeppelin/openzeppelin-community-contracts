// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {AbstractSigner} from "./AbstractSigner.sol";
import {ZKEmailUtils} from "./ZKEmailUtils.sol";

abstract contract ZKEmailSigner is AbstractSigner {
    using ZKEmailUtils for EmailAuthMsg;

    bytes32 private _accountSalt;
    IDKIMRegistry private _registry;
    IVerifier private _verifier;
    uint256 private _commandTemplate;

    /// @dev Proof verification error.
    error InvalidEmailProof(ZKEmailUtils.EmailProofError err);

    /*
     * @dev Unique identifier for owner of this contract defined as a hash of an email address and an account code.
     *
     * An account code is a random integer in a finite scalar field of https://neuromancer.sk/std/bn/bn254[BN254] curve.
     * It is a private randomness to derive a CREATE2 salt of the user’s Ethereum address
     * from the email address, i.e., userEtherAddr := CREATE2(hash(userEmailAddr, accountCode)).
     */
    function accountSalt() public view virtual returns (bytes32) {
        return _accountSalt;
    }

    /// @dev An instance of the DKIM registry contract.
    // solhint-disable-next-line func-name-mixedcase
    function DKIMRegistry() public view virtual returns (IDKIMRegistry) {
        return _registry;
    }

    /// @dev An instance of the Verifier contract.
    function verifier() public view virtual returns (IVerifier) {
        return _verifier;
    }

    /// @dev The templateId of the sign hash command.
    function commandTemplate() public view virtual returns (uint256) {
        return _commandTemplate;
    }

    /// @dev Set the {accountSalt}.
    function _setAccountSalt(bytes32 accountSalt_) internal virtual {
        _accountSalt = accountSalt_;
    }

    /// @dev Set the {DKIMRegistry} contract address.
    function _setDKIMRegistry(IDKIMRegistry registry_) internal virtual {
        _registry = registry_;
    }

    /// @dev Set the {verifier} contract address.
    function _setVerifier(IVerifier verifier_) internal virtual {
        _verifier = verifier_;
    }

    /// @dev Set the {commandTemplate} ID.
    function _setCommandTemplate(uint256 commandTemplate_) internal virtual {
        _commandTemplate = commandTemplate_;
    }

    /** @dev Authenticate the email sender and authorize the message in the email command.
     *
     * NOTE: This function only verifies the authenticity of the email and command, without
     * handling replay protection. The calling contract should implement its own mechanisms
     * to prevent replay attacks, similar to how nonces are used with ECDSA signatures.
     */
    function verifyEmail(EmailAuthMsg memory emailAuthMsg) public view virtual {
        (bool verified, ZKEmailUtils.EmailProofError err) = emailAuthMsg.isValidZKEmail(DKIMRegistry(), verifier());
        if (!verified) revert InvalidEmailProof(err);
    }

    /// @inheritdoc AbstractSigner
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        EmailAuthMsg memory emailAuthMsg = abi.decode(signature, (EmailAuthMsg));
        if (
            abi.decode(emailAuthMsg.commandParams[0], (bytes32)) == hash &&
            emailAuthMsg.templateId == commandTemplate() &&
            emailAuthMsg.proof.accountSalt == accountSalt()
        ) {
            (bool verified, ) = emailAuthMsg.isValidZKEmail(DKIMRegistry(), verifier());
            return verified;
        } else {
            return false;
        }
    }
}
