// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @dev Implementation of {AbstractSigner} whose authority is delegated to the members of a role
 * tracked by an {IAccessManager}.
 *
 * Instead of holding its own key material, this signer is bound to a single `roleId` and accepts a
 * signature only when it was produced by an address that currently holds that role in the associated
 * {accessManager}. This lets a role behave as a shared signer: membership can be granted or revoked
 * through the access manager without redeploying or reconfiguring the signer.
 *
 * The `roleId` is not stored in a regular state variable. This contract is meant to be deployed
 * behind a {Clones}-with-immutable-args proxy that carries the target role id as its immutable
 * arguments (see {AccessManagerWithRoleAccounts}, which deploys one clone per role). The {roleId}
 * getter decodes that argument and reverts with {InvalidCloneArgs} when the contract was not deployed
 * as such a clone (for example the implementation/template itself).
 *
 * WARNING: Authorization is based solely on current membership: {_isMember} ignores the per-member
 * `executionDelay` returned by {IAccessManager-hasRole}. A member that was granted the role with a
 * non-zero execution delay is nonetheless authorized to sign *immediately*, so this signer does NOT
 * honor AccessManager execution delays. Only use it for roles whose members are trusted to act
 * without a timelock, or override {_isMember} to additionally require a zero delay.
 */
contract RoleSigner is AbstractSigner {
    /// @dev The access manager whose role membership authorizes signatures for this signer.
    IAccessManager public immutable accessManager;

    /// @dev The clone's immutable arguments do not encode a single `uint64` role id.
    error InvalidCloneArgs();

    /// @param accessManager_ The access manager that tracks membership of {roleId}.
    constructor(IAccessManager accessManager_) {
        accessManager = accessManager_;
    }

    /**
     * @dev Returns the role id this signer is bound to, decoded from the clone's immutable arguments.
     *
     * Reverts with {InvalidCloneArgs} when the immutable arguments are not exactly a `uint64`, which
     * happens when the contract is not deployed as a {Clones}-with-immutable-args proxy.
     *
     * @return The role id whose members are authorized to sign for this account.
     */
    function roleId() public view returns (uint64) {
        bytes memory cloneArgs = Clones.fetchCloneArgs(address(this));
        if (cloneArgs.length != 8) revert InvalidCloneArgs();
        return uint64(bytes8(cloneArgs));
    }

    /**
     * @dev Returns whether `account` currently holds {roleId} in the {accessManager}.
     *
     * NOTE: Only membership is considered; the per-member `executionDelay` reported by
     * {IAccessManager-hasRole} is intentionally discarded (see the warning on this contract). Override
     * to also require `delay == 0` if execution delays must be honored.
     *
     * @param account The address whose membership is checked.
     * @return isMember Whether `account` is a member of the role.
     */
    function _isMember(address account) internal view virtual returns (bool isMember) {
        (isMember, ) = accessManager.hasRole(roleId(), account);
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
     *
     * @param hash The digest that was signed.
     * @param signature The `[signer][inner signature]` blob described above.
     * @return Whether the signature is valid and produced by a current role member.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length < 20) return false;
        address signer = address(bytes20(signature));
        return SignatureChecker.isValidSignatureNow(signer, hash, signature[20:]) && _isMember(signer);
    }
}
