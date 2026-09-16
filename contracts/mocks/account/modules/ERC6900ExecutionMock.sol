// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC6900ExecutionModule, IERC6900Module, ExecutionManifest, ManifestExecutionFunction, ManifestExecutionHook} from "../../../interfaces/IERC6900.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC6900ModuleMock} from "./ERC6900ModuleMock.sol";

abstract contract ERC6900ExecutionMock is ERC6900ModuleMock, IERC6900ExecutionModule {
    mapping(address sender => address signer) private _associatedSigners;

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC6900ModuleMock) returns (bool) {
        return interfaceId == type(IERC6900ExecutionModule).interfaceId || super.supportsInterface(interfaceId);
    }

    function onInstall(bytes calldata data) public virtual override(IERC6900Module, ERC6900ModuleMock) {
        _associatedSigners[msg.sender] = address(bytes20(data[0:20]));
        super.onInstall(data);
    }

    function onUninstall(bytes calldata data) public virtual override(IERC6900Module, ERC6900ModuleMock) {
        delete _associatedSigners[msg.sender];
        super.onUninstall(data);
    }

    /// @notice Describe the contents and intended configuration of the module.
    /// @dev This manifest MUST stay constant over time.
    /// @return A manifest describing the contents and intended configuration of the module.
    function executionManifest() external pure returns (ExecutionManifest memory) {
        bytes4 executionSelector = bytes4(0x99887766); //todo change them
        bytes4 executionHookSelector = bytes4(0x99887766);
        uint32 executionHookEntityId = uint32(0x99887766);
        bytes4[] memory interfaceIds = new bytes4[](1);
        interfaceIds[0] = bytes4(0x99887766);

        ExecutionManifest memory manifest = ExecutionManifest({
            executionFunctions: new ManifestExecutionFunction[](1),
            executionHooks: new ManifestExecutionHook[](1),
            interfaceIds: interfaceIds
        });
        manifest.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: executionSelector,
            skipRuntimeValidation: true,
            allowGlobalValidation: true
        });
        manifest.executionHooks[0] = ManifestExecutionHook({
            executionSelector: executionHookSelector,
            entityId: executionHookEntityId,
            isPreHook: true,
            isPostHook: true
        });
        return manifest;
    }
}
