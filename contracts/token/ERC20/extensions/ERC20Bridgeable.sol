// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC7802} from "../../../interfaces/IERC7802.sol";

/**
 * @dev ERC20 extension that implements the standard token interface according to
 * https://github.com/ethereum/ERCs/blob/bcea9feb6c3f3ded391e33690056635d722b101e/ERCS/erc-7802.md[ERC-7802].
 *
 * NOTE: To implement a crosschain gateway for a chain, consider using an implementation if {IERC7786} token
 * bridge (e.g. {AxelarGatewaySource}, {AxelarGatewayDestination}).
 */
abstract contract ERC20Bridgeable is ERC20, ERC165, IERC7802 {
    /// @dev Modifier to restrict access to the token bridge.
    modifier onlyTokenBridge() {
        _checkTokenBridge(msg.sender);
        _;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7802).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC7802-crosschainMint}. Emits a {CrosschainMint} event.
     */
    function crosschainMint(address to, uint256 value) public virtual override onlyTokenBridge {
        _mint(to, value);
        emit CrosschainMint(to, value, msg.sender);
    }

    /**
     * @dev See {IERC7802-crosschainBurn}. Emits a {CrosschainBurn} event.
     */
    function crosschainBurn(address from, uint256 value) public virtual override onlyTokenBridge {
        _burn(from, value);
        emit CrosschainBurn(from, value, msg.sender);
    }

    /**
     * @dev Checks if the caller is a trusted token bridge. MUST revert otherwise.
     *
     * Developers should implement this function using an access control mechanism that allows
     * customizing the list of allowed senders. Consider using {AccessControl} or {AccessManaged}.
     */
    function _checkTokenBridge(address caller) internal virtual;
}
