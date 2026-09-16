// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC6900ValidationModule, IERC6900Module} from "../../../interfaces/IERC6900.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC6900ModuleMock} from "./ERC6900ModuleMock.sol";

abstract contract ERC6900ValidationMock is ERC6900ModuleMock, IERC6900ValidationModule {
    mapping(address sender => address signer) private _associatedSigners;

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC6900ModuleMock) returns (bool) {
        return interfaceId == type(IERC6900ValidationModule).interfaceId || super.supportsInterface(interfaceId);
    }

    function onInstall(bytes calldata data) public virtual override(IERC6900Module, ERC6900ModuleMock) {
        _associatedSigners[msg.sender] = address(bytes20(data[0:20]));
        super.onInstall(data);
    }

    function onUninstall(bytes calldata data) public virtual override(IERC6900Module, ERC6900ModuleMock) {
        delete _associatedSigners[msg.sender];
        super.onUninstall(data);
    }

    // le'ts no override moduleId()

    function validateUserOp(
        uint32 entityId,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) public view virtual returns (uint256) {
        entityId; // silence warning
        return
            SignatureChecker.isValidSignatureNow(_associatedSigners[msg.sender], userOpHash, userOp.signature)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    function validateRuntime(
        address account,
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data,
        bytes calldata authorization
    ) public view virtual {
        // return
        //     SignatureChecker.isValidSignatureNow(_associatedSigners[msg.sender], userOpHash, userOp.signature)
        //         ? ERC4337Utils.SIG_VALIDATION_SUCCESS
        //         : ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    function validateSignature(
        address account,
        uint32 entityId,
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual returns (bytes4) {
        account; // silence warning
        entityId; // silence warning
        return
            SignatureChecker.isValidSignatureNow(_associatedSigners[sender], hash, signature)
                ? IERC1271.isValidSignature.selector
                : bytes4(0xffffffff);
    }
}
