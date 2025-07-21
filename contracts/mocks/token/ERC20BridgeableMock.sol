// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Bridgeable} from "../../token/ERC20/extensions/ERC20Bridgeable.sol";

abstract contract ERC20BridgeableMock is ERC20Bridgeable, AccessControl {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC20Bridgeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _checkTokenBridge(address sender) internal view override onlyRole(BRIDGE_ROLE) {}
}
