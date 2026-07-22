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
 * How the `roleId` is resolved is left to implementations (see {roleId}). {RoleAccount} decodes it
 * from the immutable arguments of a `Clones.cloneWithImmutableArgs` proxy (see
 * {AccessManagerWithRoleAccounts}, which deploys one clone per role).
 */
abstract contract RoleSigner is AbstractSigner {
    /// @dev Thrown when the access manager is the zero address.
    error InvalidAccessManager();

    /// @dev The access manager whose role membership authorizes signatures for this signer.
    IAccessManager public immutable accessManager;

    /// @dev Sets the {accessManager} whose role membership authorizes signatures for this signer.
    constructor(IAccessManager accessManager_) {
        require(address(accessManager_) != address(0), InvalidAccessManager());
        accessManager = accessManager_;
    }

    /**
     * @dev Returns the role id this signer is bound to. Members of this role in the {accessManager}
     * are authorized to produce signatures on behalf of this signer.
     *
     * Implementations are responsible for defining how the role id is resolved (see {RoleAccount},
     * which decodes it from the clone's immutable arguments).
     */
    function roleId() public view virtual returns (uint64);

    /**
     * @dev Returns whether `account` currently holds {roleId} in the {accessManager} and has no execution delay.
     * This signer does not allow roles with execution delays to interact with it.
     */
    function _isUnrestrictedMember(address account) internal view virtual returns (bool) {
        (bool hasRole, uint32 executionDelay) = accessManager.hasRole(roleId(), account);
        return hasRole && executionDelay == 0;
    }

    /**
     * @dev See {AbstractSigner-_rawSignatureValidation}.
     *
     * The `signature` is expected to be the concatenation `[20-byte signer address][inner signature]`.
     * The leading 20 bytes identify the account that produced the inner signature. Validation succeeds
     * only when the inner signature is valid for `hash` (verified through {SignatureChecker}, so both
     * EOAs and ERC-1271 smart contract signers are supported) AND that signer currently holds {roleId}.
     *
     * A `signature` shorter than the 20-byte address prefix is rejected without reverting.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        address signer = address(bytes20(signature));
        return
            signature.length >= 20 &&
            SignatureChecker.isValidSignatureNow(signer, hash, signature[20:]) &&
            _isUnrestrictedMember(signer);
    }
}
