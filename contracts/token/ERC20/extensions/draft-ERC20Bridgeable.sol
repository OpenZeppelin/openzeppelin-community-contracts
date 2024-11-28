// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7802} from "../../../crosschain/interfaces/draft-IERC7802.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev ERC20 extension that implements the standard token interface according to
 * https://github.com/ethereum/ERCs/blob/bcea9feb6c3f3ded391e33690056635d722b101e/ERCS/erc-7802.md[ERC-7801].
 *
 * The extension requires users to implement {IERC7802-crosschainMint} and {IERC7802-crosschainBurn} to allow
 * crosschain transfers. It is recommended to implement these with an access control mechanism that allows
 * customizing the list of allowed senders.
 *
 * NOTE: To implement a crosschain gateway for a chain, consider using an implementation if {IERC7786} token
 * bridge (e.g. {AxelarGatewaySource}, {AxelarGatewayDestination}). The bridge can be an allowed sender in
 * this contract. Consider using {Ownable}, {AccessControl} or {AccessManager} to manage the list of allowed senders.
 */
abstract contract ERC20Bridgeable is ERC165, ERC20, IERC7802 {
    using Strings for address;

    /// @dev A crosschain version of this ERC20 has been registered for a chain.
    event RegisteredCrosschainERC20(string caip2, string erc20Address);

    error UnsupportedNativeValue();
    error CrosschainERC20AlreadyRegistered(string caip2);

    /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedChain(string caip2);

    bytes4 crosschainMintAttr = bytes4(keccak256("crosschainMint(address,uint256)"));
    bytes4 crosschainBurnAttr = bytes4(keccak256("crosschainBurn(address,uint256)"));

    mapping(string caip2 => string crosschainERC20) private _crosschainERC20s;

    /// @dev Modifier to restrict access to the token bridge.
    modifier onlyTokenBridge() {
        _checkBridgeAction(msg.sender, msg.sig);
        _;
    }

    /**
     * @dev Checks if the caller is a trusted token bridge. MUST revert otherwise.
     *
     * Developers should implement this function using an access control mechanism that allows
     * customizing the list of allowed senders. Consider using {Ownable}, {AccessControl} or {AccessManager}.
     */
    function _checkBridgeAction(address caller, bytes4 selector) internal virtual;

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7802).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Returns the address string of the crosschain gateway for a given CAIP-2 chain identifier.
    function getCrosschainERC20(string memory caip2) public view virtual returns (string memory crosschainERC20) {
        crosschainERC20 = _crosschainERC20s[caip2];
        require(bytes(crosschainERC20).length > 0, UnsupportedChain(caip2));
    }

    /// @dev Registers the address string of the crosschain version of this ERC20 for a given CAIP-2 chain identifier.
    /// Internal version without access control.
    function _registerCrosschainERC20(string calldata caip2, string calldata crosschainERC20) internal virtual {
        require(bytes(_crosschainERC20s[caip2]).length == 0, CrosschainERC20AlreadyRegistered(caip2));
        _crosschainERC20s[caip2] = crosschainERC20;
        emit RegisteredCrosschainERC20(caip2, crosschainERC20);
    }

    /// @dev Getter to check whether an attribute is supported or not.
    function supportsAttribute(bytes4 selector) public view virtual returns (bool) {
        return selector == crosschainMintAttr || selector == crosschainBurnAttr;
    }

    /// @inheritdoc IERC7802
    function crosschainMint(address to, uint256 value) public virtual override onlyTokenBridge {
        _crosschainMint(to, msg.sender, value);
    }

    /// @inheritdoc IERC7802
    function crosschainBurn(address from, uint256 value) public virtual override onlyTokenBridge {
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
