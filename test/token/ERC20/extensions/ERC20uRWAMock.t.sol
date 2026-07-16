// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20uRWA} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC20uRWA.sol";

contract ERC20uRWAMock is ERC20uRWA, AccessControl {
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");

    mapping(address => bool) private _sendOverride;
    mapping(address => bool) private _receiveOverride;
    mapping(address => bool) private _sendOverrideSet;
    mapping(address => bool) private _receiveOverrideSet;

    constructor(
        string memory name,
        string memory symbol,
        address freezer,
        address enforcer
    ) ERC20(name, symbol) {
        _grantRole(FREEZER_ROLE, freezer);
        _grantRole(ENFORCER_ROLE, enforcer);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function setCanSend(address account, bool allowed) public {
        _sendOverride[account] = allowed;
        _sendOverrideSet[account] = true;
    }

    function setCanReceive(address account, bool allowed) public {
        _receiveOverride[account] = allowed;
        _receiveOverrideSet[account] = true;
    }

    function canSend(address account) public view override returns (bool) {
        if (_sendOverrideSet[account]) return _sendOverride[account];
        return super.canSend(account);
    }

    function canReceive(address account) public view override returns (bool) {
        if (_receiveOverrideSet[account]) return _receiveOverride[account];
        return super.canReceive(account);
    }

    function blockUser(address account) public {
        _blockUser(account);
    }

    function allowUser(address account) public {
        _allowUser(account);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC20uRWA, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _checkEnforcer(address, address, uint256) internal view override onlyRole(ENFORCER_ROLE) {}

    function _checkFreezer(address, uint256) internal view override onlyRole(FREEZER_ROLE) {}
}
