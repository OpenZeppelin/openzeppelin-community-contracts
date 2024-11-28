// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC7802} from "../../../crosschain/interfaces/draft-IERC7802.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev ERC20 extension that implements the standard token interface according to
 * https://github.com/ethereum/ERCs/blob/bcea9feb6c3f3ded391e33690056635d722b101e/ERCS/erc-7802.md[ERC-7801].
 *
 * NOTE: To implement a crosschain gateway for a chain, consider using an implementation if {IERC7786} token
 * bridge (e.g. {AxelarGatewaySource}, {AxelarGatewayDestination}).
 */
abstract contract ERC20Bridgeable is ERC165, ERC20, IERC7802 {
    /// @dev Modifier to restrict access to the token bridge.
    modifier onlyTokenBridge(address caller) {
        _checkTokenBridge(caller);
        _;
    }

    /**
     * @dev Checks if the caller is a trusted token bridge. MUST revert otherwise.
     *
     * Developers should implement this function using an access control mechanism that allows
     * customizing the list of allowed senders. Consider using {Ownable}, {AccessControl} or {AccessManager}.
     */
    function _checkTokenBridge(address caller) internal virtual;

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7802).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7802
    function crosschainMint(address to, uint256 value) public virtual override onlyTokenBridge(msg.sender) {
        _crosschainMint(to, msg.sender, value);
    }

    /// @inheritdoc IERC7802
    function crosschainBurn(address from, uint256 value) public virtual override onlyTokenBridge(msg.sender) {
        _crosschainBurn(from, msg.sender, value);
    }

    /**
     * @dev Internal version of {crosschainMint} without access control.
     *
     * Emits a {CrosschainMint} event.
     */
    function _crosschainMint(address to, address sender, uint256 value) internal virtual {
        _mint(to, value);
        emit CrosschainMint(to, value, sender);
    }

    /**
     * @dev Internal version of {crosschainBurn} without access control.
     *
     * Emits a {CrosschainBurn} event.
     */
    function _crosschainBurn(address from, address sender, uint256 value) internal virtual {
        _burn(from, value);
        emit CrosschainBurn(from, value, sender);
    }
}
