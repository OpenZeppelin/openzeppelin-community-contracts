// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager, AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AbstractSigner} from "@openzeppelin/contracts/utils/cryptography/signers/AbstractSigner.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract RoleSigner is AbstractSigner {
    IAccessManager public immutable accessManager;

    constructor(IAccessManager accessManager_) {
        accessManager = accessManager_;
    }

    function roleId() public view returns (uint64) {
        bytes memory cloneArgs = Clones.fetchCloneArgs(address(this));
        require(cloneArgs.length == 8, "Invalid clone args");
        return uint64(bytes8(cloneArgs));
    }

    function _isMember(address account) internal view virtual returns (bool isMember) {
        (isMember, ) = accessManager.hasRole(roleId(), account);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        address signer = address(bytes20(signature));
        return SignatureChecker.isValidSignatureNow(signer, hash, signature[20:]) && _isMember(signer);
    }
}

contract RoleAccount is ERC7821, ERC7739, RoleSigner {
    constructor(IAccessManager accessManager_) RoleSigner(accessManager_) EIP712("RoleAccount", "1") {}

    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return super._erc7821AuthorizedExecutor(caller, mode, executionData) || _isMember(caller);
    }
}

contract AccessManagerWithRoleAccounts is AccessManager {
    address private immutable _template = address(new RoleAccount(this));

    constructor(address initialAdmin) AccessManager(initialAdmin) {}

    function getConfidentialHandler(uint64 roleId) public view returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                _template,
                abi.encodePacked(roleId),
                _roleToSalt(roleId)
            );
    }

    function deployConfidentialHandler(uint64 roleId) public returns (address) {
        return Clones.cloneDeterministicWithImmutableArgs(_template, abi.encodePacked(roleId), _roleToSalt(roleId));
    }

    function _roleToSalt(uint64 roleId) internal view virtual returns (bytes32) {
        return bytes32(uint256(roleId));
    }
}
