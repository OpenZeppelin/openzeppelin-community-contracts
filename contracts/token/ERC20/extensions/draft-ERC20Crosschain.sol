// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7802} from "../../../crosschain/interfaces/draft-IERC7802.sol";
import {IERC7786GatewaySource} from "./../../../crosschain/interfaces/draft-IERC7786.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

abstract contract CrosschainERC20 is ERC165, ERC20, IERC7786GatewaySource, IERC7802 {
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

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
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
    function supportsAttribute(bytes4 selector) external view returns (bool) {
        return selector == crosschainMintAttr || selector == crosschainBurnAttr;
    }

    /**
     * @dev Internal version of {crosschainMint} without access control.
     *
     * Emits a {CrosschainMint} event.
     */
    function _crosschainMint(address to, uint256 value) internal {
        _mint(to, value);
        emit CrosschainMint(to, value, msg.sender);
    }

    /**
     * @dev Internal version of {crosschainBurn} without access control.
     *
     * Emits a {CrosschainBurn} event.
     */
    function _crosschainBurn(address from, address sender, uint256 value) internal {
        _burn(from, value);
        emit CrosschainBurn(from, value, msg.sender);
    }

    function crosschainTransfer(address to, uint256 amount, string calldata caip2Destination) public {
        address from = msg.sender;
        _transfer(from, to, amount, caip2Destination);
    }

    function _transfer(address from, address to, uint256 value, string calldata caip2Destination) internal {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        _update(from, to, value, caip2Destination);
    }

    function _update(address from, address to, uint256 value, string calldata caip2Destination) internal {
        bytes[] memory attributes = new bytes[](0);

        // Burn tokens first
        _burn(from, value);

        // Compensate
        if (CAIP2.local() == caip2Destination) _mint(to, value);
        else
            sendMessage(
                caip2Destination,
                getCrosschainERC20(caip2Destination),
                abi.encodeCall(IERC7802.crosschainMint, (to, value)),
                attributes
            ); // Send message if destination is another chain
    }
}
