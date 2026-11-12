// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20uRWAUpgradeable} from "../../token/ERC20/extensions/ERC20uRWAUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC20uRWAMockUpgradeable is Initializable, ERC20uRWAUpgradeable, AccessControlUpgradeable {
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");

    mapping(address account => bool) private _sendDenied;
    mapping(address account => bool) private _receiveDenied;

    function __ERC20uRWAMock_init(address freezer, address enforcer) internal onlyInitializing {
        __ERC20uRWAMock_init_unchained(freezer, enforcer);
    }

    function __ERC20uRWAMock_init_unchained(address freezer, address enforcer) internal onlyInitializing {
        _grantRole(FREEZER_ROLE, freezer);
        _grantRole(ENFORCER_ROLE, enforcer);
    }

    function setSendDenied(address account, bool denied) public {
        _sendDenied[account] = denied;
    }

    function setReceiveDenied(address account, bool denied) public {
        _receiveDenied[account] = denied;
    }

    function canSend(address account) public view override returns (bool) {
        return !_sendDenied[account] && super.canSend(account);
    }

    function canReceive(address account) public view override returns (bool) {
        return !_receiveDenied[account] && super.canReceive(account);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC20uRWAUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _checkEnforcer(address, address, uint256) internal view override onlyRole(ENFORCER_ROLE) {}

    function _checkFreezer(address, uint256) internal view override onlyRole(FREEZER_ROLE) {}
}
