// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {RoleSigner} from "../utils/cryptography/signers/RoleSigner.sol";

/**
 * @dev On-chain account that represents a role of an {IAccessManager}.
 *
 * A `RoleAccount` is bound to a single role (see {RoleSigner}) and acts on behalf of whoever currently
 * holds that role: any member can produce ERC-1271 signatures for the account or trigger batched calls
 * through it. Because authorization is resolved live against the access manager, granting or revoking
 * the role immediately grants or revokes control of the account, without touching the account itself.
 *
 * It composes:
 *
 * * {RoleSigner}: gates signature validation on role membership.
 * * {ERC7739}: wraps signatures as ERC-7739 nested typed data / personal-sign messages to provide
 *   replay-safe ERC-1271 validation on top of {RoleSigner}.
 * * {ERC7821}: minimal batch executor.
 *
 * These accounts are intended to be deployed as {Clones}-with-immutable-args proxies, one per role, by
 * {AccessManagerWithRoleAccounts}.
 */
contract RoleAccount is ERC7821, ERC7739, RoleSigner {
    constructor(IAccessManager accessManager_) RoleSigner(accessManager_) EIP712("RoleAccount", "1.0.0") {}

    /**
     * @dev See {ERC7821-_erc7821AuthorizedExecutor}. In addition to the default authorization (a
     * self-call by the account), any current member of the account's role is authorized to execute.
     */
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return super._erc7821AuthorizedExecutor(caller, mode, executionData) || _isMember(caller);
    }
}
