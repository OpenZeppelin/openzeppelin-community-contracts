// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @dev Implementation of {AbstractSigner} whose authority is delegated to the members of a role
 * tracked by an {IAccessManager}.
 *
 * Instead of holding its own key material, this signer is bound to a single `roleId` and accepts a
 * signature only when it was produced by an address that currently holds that role in the associated
 * {accessManager} with 0 delay. This lets a role behave as a shared signer: membership can be granted
 * or revoked through the access manager without redeploying or reconfiguring the signer.
 *
 * WARNING: A role account grants control to *every current member* of its role. For the special
 * `PUBLIC_ROLE` (`type(uint64).max`), which every address belongs to, this means the account is
 * controllable by anyone.
 */
abstract contract SignerAccessManaged is AbstractSigner {
    IAccessManager private immutable _accessManager;
    uint64 private immutable _roleId;

    /**
     * @dev Create a new signer where access is managed by the given access manager and role id.
     * Access is checked via {_isAuthorizedMember}.
     */
    constructor(address accessManager_, uint64 roleId_) {
        _accessManager = IAccessManager(accessManager_);
        _roleId = roleId_;
    }

    /**
     * @dev Returns the {IAccessManager} whose role membership authorizes signatures for this signer.
     */
    function accessManager() public view virtual returns (IAccessManager) {
        return _accessManager;
    }

    /**
     * @dev Returns the role id this signer is bound to. Members of this role in the {accessManager}
     * are authorized to produce signatures on behalf of this signer.
     */
    function roleId() public view virtual returns (uint64) {
        return _roleId;
    }

    /**
     * @dev Returns whether `account` currently holds {roleId} in the {accessManager} and has no execution delay.
     * This signer does not allow roles with execution delays to interact with it.
     */
    function _isAuthorizedMember(address account) internal view virtual returns (bool) {
        (bool hasRole, uint32 executionDelay) = accessManager().hasRole(roleId(), account);
        return hasRole && executionDelay == 0;
    }

    /**
     * @dev See {AbstractSigner-_rawSignatureValidation}.
     *
     * The `signature` is expected to be the concatenation `[20-byte signer address][inner signature]`.
     * The leading 20 bytes identify the account that produced the inner signature. Validation succeeds
     * only when the inner signature is valid for `hash` (verified through {SignatureChecker}, so both
     * EOAs and ERC-1271 smart contract signers are supported) AND that signer is an authorized
     * {roleId} member (see {_isAuthorizedMember}).
     *
     * A `signature` shorter than the 20-byte address prefix is rejected without reverting.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length < 20) return false;
        address signer = address(bytes20(signature));
        return
            SignatureChecker.isValidSignatureNowCalldata(signer, hash, signature[20:]) && _isAuthorizedMember(signer);
    }
}
