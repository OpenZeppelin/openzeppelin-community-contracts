// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignerAccessManaged} from "../utils/cryptography/signers/SignerAccessManaged.sol";

/**
 * @dev On-chain account managed by the members of a role of an {IAccessManager}.
 *
 * A `RoleAccount` is bound to a single role (see {SignerAccessManaged}) and acts on behalf of whoever currently
 * holds that role: any member can produce ERC-1271 signatures for the account or trigger batched calls
 * through it. Because authorization is resolved live against the access manager, granting or revoking
 * the role immediately grants or revokes control of the account, without touching the account itself.
 *
 * It composes:
 *
 * * {SignerAccessManaged}: gates signature validation on role membership.
 * * {ERC7739}: wraps signatures as ERC-7739 nested typed data / personal-sign messages to provide
 *   replay-safe ERC-1271 validation on top of {SignerAccessManaged}.
 * * {ERC7821}: minimal batch executor.
 *
 * These accounts are intended to be deployed as `Clones.cloneWithImmutableArgs`, once per (access manager,
 * role) pair, by {RoleAccountFactory}. The access manager and role id are encoded in the clone's immutable
 * arguments, so calling the getters on the implementation directly (outside a clone) reverts.
 */
contract RoleAccount is ERC7821, ERC7739, SignerAccessManaged {
    address private immutable _self = address(this);

    error RoleAccountDirectCallNotAllowed();
    error RoleAccountInvalidImmutableArgs();

    constructor() EIP712("RoleAccount", "1") SignerAccessManaged(address(0), 0) {}

    /**
     * @dev Returns the access manager this account is bound to, decoded from the clone's immutable arguments.
     *
     * Reverts with {RoleAccountDirectCallNotAllowed} when called on the implementation directly (i.e. not through a
     * `Clones.cloneWithImmutableArgs` proxy), and with {RoleAccountInvalidImmutableArgs} when the immutable arguments
     * are not 28 bytes long.
     */
    function accessManager() public view virtual override returns (IAccessManager accessManager_) {
        (accessManager_, ) = _fetchArgs();
    }

    /**
     * @dev Returns the role id this signer is bound to, decoded from the clone's immutable arguments.
     *
     * Reverts with {RoleAccountDirectCallNotAllowed} when called on the implementation directly (i.e. not through a
     * `Clones.cloneWithImmutableArgs` proxy), and with {RoleAccountInvalidImmutableArgs} when the immutable arguments
     * are not 28 bytes long.
     */
    function roleId() public view virtual override returns (uint64 roleId_) {
        (, roleId_) = _fetchArgs();
    }

    /// @dev Decodes the access manager and role id packed in the clone's immutable arguments.
    function _fetchArgs() private view returns (IAccessManager accessManager_, uint64 roleId_) {
        require(_self != address(this), RoleAccountDirectCallNotAllowed());

        bytes memory cloneArgs = Clones.fetchCloneArgs(address(this));
        require(cloneArgs.length >= 28, RoleAccountInvalidImmutableArgs());

        bytes28 data = bytes28(cloneArgs);
        return (IAccessManager(address(bytes20(data))), uint64(bytes8(data << 160)));
    }

    /**
     * @dev See {ERC7821-_erc7821AuthorizedExecutor}. In addition to the default authorization (a
     * self-call by the account), any current member of the account's role is authorized to execute.
     */
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return super._erc7821AuthorizedExecutor(caller, mode, executionData) || _isAuthorizedMember(caller);
    }

    /// @dev Allow the account to receive ETH.
    receive() external payable {}
}
