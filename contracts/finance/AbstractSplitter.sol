// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title AbstractSplitter
 * @dev This contract allows to split payments in any fungible asset among a group of accounts. The sender does not
 * need to be aware that the asset will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares through the {_shares} and {_totalShares} virtual function. Of all the assets that this
 * contract receives, each account will then be able to claim an amount proportional to the percentage of total shares
 * they own assigned.
 *
 * `AbstractSplitter` follows a _pull payment_ model. This means that payments are not automatically forwarded to
 * the accounts but kept in this contract, and the actual transfer is triggered as a separate step by calling the
 * {release} function.
 *
 * Warning: An abstractSplitter can only process a single asset class, implicitly defined by the {_balance} and
 * {_doRelease} functions. Any other asset class will not be recoverable.
 */
abstract contract AbstractSplitter {
    using SafeCast for *;

    mapping(address account => int256) private _released;
    int256 private _totalReleased;

    event PaymentReleased(address to, uint256 amount);

    /**
     * @dev Internal hook: get shares for an account
     */
    function _shares(address account) internal view virtual returns (uint256);

    /**
     * @dev Internal hook: get total shares
     */
    function _totalShares() internal view virtual returns (uint256);

    /**
     * @dev Internal hook: get splitter balance
     */
    function _balance() internal view virtual returns (uint256);

    /**
     * @dev Internal hook: call when token are released
     */
    function _doRelease(address to, uint256 amount) internal virtual;

    /**
     * @dev Asset units up for release.
     */
    function pendingRelease(address account) public view virtual returns (uint256) {
        uint256 amount = _shares(account);
        // if personalShares == 0, there is a risk of totalShares == 0. To avoid div by 0 just return 0
        uint256 allocation = amount > 0 ? _allocation(amount, _totalShares()) : 0;
        return (allocation.toInt256() - _released[account]).toUint256();
    }

    /**
     * @dev Triggers a transfer of asset to `account` according to their percentage of the total shares and their
     * previous withdrawals.
     */
    function release(address account) public virtual returns (uint256) {
        uint256 toRelease = pendingRelease(account);
        if (toRelease > 0) {
            _addRelease(account, toRelease.toInt256());
            emit PaymentReleased(account, toRelease);
            _doRelease(account, toRelease);
        }
        return toRelease;
    }

    /**
     * @dev Update release manifest to account to shares movement when payment has not been released. This must be
     * called whenever shares are minted, burned or transferred.
     */
    function _beforeShareTransfer(address from, address to, uint256 amount) internal virtual {
        if (amount > 0) {
            uint256 supply = _totalShares();
            if (supply > 0) {
                int256 virtualRelease = _allocation(amount, supply).toInt256();
                if (from != address(0)) _subRelease(from, virtualRelease);
                if (to != address(0)) _addRelease(to, virtualRelease);
            }
        }
    }

    function _allocation(uint256 amount, uint256 supply) private view returns (uint256) {
        return Math.mulDiv(amount, (_balance().toInt256() + _totalReleased).toUint256(), supply);
    }

    function _addRelease(address account, int256 amount) private {
        _released[account] += amount;
        _totalReleased += amount;
    }

    function _subRelease(address account, int256 amount) private {
        _released[account] -= amount;
        _totalReleased -= amount;
    }
}
