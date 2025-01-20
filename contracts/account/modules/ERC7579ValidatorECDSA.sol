// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7579Module, IERC7579ModuleConfig, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {ERC7579Validator} from "./ERC7579Validator.sol";

contract ERC7579ValidatorECDSA is ERC7579Validator, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address account => EnumerableSet.AddressSet) private _keys;

    error ERC7579ValidatorECDSAMissingKeyForAccount(address account);

    /// @dev modifier that reverts a function if it risks bricking an account.
    modifier installMustHaveKeys(address account) {
        _;
        _checkHasKeys(account);
    }

    /// @inheritdoc IERC7579Module
    function onInstall(bytes calldata data) public virtual override installMustHaveKeys(msg.sender) {
        super.onInstall(data);
    }

    /// @inheritdoc IERC7579Module
    function onUninstall(bytes calldata data) public virtual override {
        super.onUninstall(data);
        _clear(msg.sender);
    }

    /// @inheritdoc ERC7579Validator
    function _isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return isKey(sender, recovered) && err == ECDSA.RecoverError.NoError;
    }

    /// @dev Add a signing key for the calling account.
    function addKey(address key) public virtual {
        _keys[msg.sender].add(key);
    }

    /// @dev Remove a signing key for the calling account.
    function removeKey(address key) public virtual installMustHaveKeys(msg.sender) {
        _keys[msg.sender].remove(key);
    }

    /// @dev Getter: is key a valid signer for a given account.
    function isKey(address account, address key) public view virtual returns (bool) {
        return _keys[account].contains(key);
    }

    /// @dev Getter: how many keys are valid signers for a given account.
    function keyCount(address account) public view virtual returns (uint256) {
        return _keys[account].length();
    }

    /// @dev Getter: get the active key n° `index` for a given account.
    function keyAt(address account, uint256 index) public view virtual returns (address) {
        return _keys[account].at(index);
    }

    /**
     * @dev Getter: get all the active keys for a given account.
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function keys(address account) public view returns (address[] memory) {
        return _keys[account].values();
    }

    /// @dev Remove all keys from an active signer.
    function _clear(address account) internal virtual {
        EnumerableSet.AddressSet storage accountKeys = _keys[account];
        for (uint256 i = 0; i < accountKeys.length(); ++i) {
            accountKeys.remove(accountKeys.at(i));
        }
    }

    /// @dev Validity check: revert if `account` is using this validation module, and if no key is active.
    function _checkHasKeys(address account) internal view virtual {
        if (
            keyCount(account) == 0 &&
            IERC7579ModuleConfig(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(this), "")
        ) {
            revert ERC7579ValidatorECDSAMissingKeyForAccount(account);
        }
    }
}
