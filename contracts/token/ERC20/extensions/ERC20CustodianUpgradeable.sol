// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that allows to implement a custodian
 * mechanism that can be managed by an authorized account with the
 * {freeze} function.
 *
 * This mechanism allows a custodian (e.g. a DAO or a
 * well-configured multisig) to freeze and unfreeze the balance
 * of a user.
 *
 * The frozen balance is not available for transfers or approvals
 * to other entities to operate on its behalf if. The frozen balance
 * can be reduced by calling {freeze} again with a lower amount.
 *
 * IMPORTANT: Deprecated. Use {ERC20Freezable} instead.
 */
abstract contract ERC20CustodianUpgradeable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Custodian
    struct ERC20CustodianStorage {
        /**
         * @dev The amount of tokens frozen by user address.
         */
        mapping(address user => uint256 amount) _frozen;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Custodian")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20CustodianStorageLocation = 0x0b7216c57b5e183dc2bf8d48004dde6895cb2a9f7f7c4b1414c9e9b961e30100;

    function _getERC20CustodianStorage() private pure returns (ERC20CustodianStorage storage $) {
        assembly {
            $.slot := ERC20CustodianStorageLocation
        }
    }

    /**
     * @dev Emitted when tokens are frozen for a user.
     * @param user The address of the user whose tokens were frozen.
     * @param amount The amount of tokens that were frozen.
     */
    event TokensFrozen(address indexed user, uint256 amount);

    /**
     * @dev Emitted when tokens are unfrozen for a user.
     * @param user The address of the user whose tokens were unfrozen.
     * @param amount The amount of tokens that were unfrozen.
     */
    event TokensUnfrozen(address indexed user, uint256 amount);

    /**
     * @dev The operation failed because the user has insufficient unfrozen balance.
     */
    error ERC20InsufficientUnfrozenBalance(address user);

    /**
     * @dev The operation failed because the user has insufficient frozen balance.
     */
    error ERC20InsufficientFrozenBalance(address user);

    /**
     * @dev Error thrown when a non-custodian account attempts to perform a custodian-only operation.
     */
    error ERC20NotCustodian();

    /**
     * @dev Modifier to restrict access to custodian accounts only.
     */
    modifier onlyCustodian() {
        if (!_isCustodian(_msgSender())) revert ERC20NotCustodian();
        _;
    }

    function __ERC20Custodian_init() internal onlyInitializing {
    }

    function __ERC20Custodian_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns the amount of tokens frozen for a user.
     */
    function frozen(address user) public view virtual returns (uint256) {
        ERC20CustodianStorage storage $ = _getERC20CustodianStorage();
        return $._frozen[user];
    }

    /**
     * @dev Adjusts the amount of tokens frozen for a user.
     * @param user The address of the user whose tokens to freeze.
     * @param amount The amount of tokens frozen.
     *
     * Requirements:
     *
     * - The user must have sufficient unfrozen balance.
     */
    function freeze(address user, uint256 amount) external virtual onlyCustodian {
        ERC20CustodianStorage storage $ = _getERC20CustodianStorage();
        if (availableBalance(user) < amount) revert ERC20InsufficientUnfrozenBalance(user);
        $._frozen[user] = amount;
        emit TokensFrozen(user, amount);
    }

    /**
     * @dev Returns the available (unfrozen) balance of an account.
     * @param account The address to query the available balance of.
     * @return available The amount of tokens available for transfer.
     */
    function availableBalance(address account) public view returns (uint256 available) {
        available = balanceOf(account) - frozen(account);
    }

    /**
     * @dev Checks if the user is a custodian.
     * @param user The address of the user to check.
     * @return True if the user is authorized, false otherwise.
     */
    function _isCustodian(address user) internal view virtual returns (bool);

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && availableBalance(from) < value) revert ERC20InsufficientUnfrozenBalance(from);
        super._update(from, to, value);
    }
}
