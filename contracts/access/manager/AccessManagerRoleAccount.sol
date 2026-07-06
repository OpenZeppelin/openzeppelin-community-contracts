// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager, AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract RoleAccount is Account, ERC7739 {
    IAccessManager public immutable accessManager;

    constructor(IAccessManager accessManager_) EIP712("RoleAccount", "1") {
        accessManager = accessManager_;
    }

    function roleId() public view returns (uint64) {
        bytes memory cloneArgs = Clones.fetchCloneArgs(address(this));
        require(cloneArgs.length == 8, "Invalid clone args");
        return uint64(bytes8(cloneArgs));
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        address signer = address(bytes20(signature));
        (bool isMember, ) = accessManager.hasRole(roleId(), signer);
        if (isMember) {
            return SignatureChecker.isValidSignatureNow(signer, hash, signature[20:]);
        } else {
            return false;
        }
    }
}

contract AccessManagerWithRoleAccounts is AccessManager {
    address private immutable _template = address(new RoleAccount(this));

    constructor(address initialAdmin) AccessManager(initialAdmin) {}

    function getConfidentialHandler(uint64 roleId) public view returns (address) {
        return Clones.predictDeterministicAddressWithImmutableArgs(_template, abi.encode(roleId), _roleToSalt(roleId));
    }

    function deployConfidentialHandler(uint64 roleId) public returns (address) {
        return Clones.cloneDeterministicWithImmutableArgs(_template, abi.encode(roleId), _roleToSalt(roleId));
    }

    function _roleToSalt(uint64 roleId) internal view virtual returns (bytes32) {
        require(roleId != PUBLIC_ROLE, AccessManagerLockedRole(roleId));
        return bytes32(uint256(roleId));
    }
}
