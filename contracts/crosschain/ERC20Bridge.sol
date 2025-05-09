// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7786Receiver} from "./utils/ERC7786Receiver.sol";
import {IERC7786GatewaySource} from "../interfaces/IERC7786.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {IERC7802} from "../interfaces/IERC7802.sol";

abstract contract ERC20Bridge is ERC7786Receiver {
    using Strings for *;
    using CAIP2 for string;
    using CAIP10 for uint256;

    mapping(address token => mapping(string caip2 => string caip10)) private _tokenEquivalents;
    mapping(string caip2 => string caip10) private _bridgeEquivalents;

    function getTokenEquivalent(
        address _tokenAddress,
        string memory _chainId
    ) public view virtual returns (string memory) {
        return _tokenEquivalents[_tokenAddress][_chainId];
    }

    function getBridgeEquivalent(string memory _chainId) public view virtual returns (string memory) {
        return _bridgeEquivalents[_chainId];
    }

    function registerTokenEquivalent(
        address _tokenAddress,
        string memory _chainId,
        string memory _remoteTokenAddress
    ) public virtual {
        _authorizeRegister(msg.sender);
        _tokenEquivalents[_tokenAddress][_chainId] = _remoteTokenAddress;
    }

    function registerBridgeEquivalent(string memory _chainId, string memory _remoteChainId) public virtual {
        _authorizeRegister(msg.sender);
        _bridgeEquivalents[_chainId] = _remoteChainId;
    }

    function crossChainTransfer(
        IERC7786GatewaySource gateway,
        IERC7802 token,
        string memory destinationChain, // CAIP-2 chain identifier
        string memory to, // CAIP-10 account address (does not include the chain identifier)
        uint256 _amount
    ) public virtual {
        require(_isKnownGateway(address(gateway)));

        // Burn the tokens
        token.crosschainBurn(msg.sender, _amount);

        // Send the message
        gateway.sendMessage(
            getBridgeEquivalent(destinationChain),
            to,
            _encodePayload(getTokenEquivalent(address(token), destinationChain), to, _amount),
            new bytes[](0)
        );
    }

    /// @dev Virtual function that should contain the logic to execute when a cross-chain message is received.
    function _processMessage(
        address /* gateway */,
        string calldata sourceChain,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata /* attributes */
    ) internal virtual override {
        // Gateway is already validated

        require(getBridgeEquivalent(sourceChain).equal(sender));

        (string memory tokenCaip10, string memory to, uint256 amount) = _decodePayload(payload);
        address tokenAddr = tokenCaip10.parseAddress();

        // Mint the tokens
        IERC7802 token = IERC7802(tokenAddr);
        token.crosschainMint(to.parseAddress(), amount);
    }

    function _encodePayload(
        string memory _tokenAddress,
        string memory _to,
        uint256 _amount
    ) internal pure returns (bytes memory) {
        return abi.encode(_tokenAddress, _to, _amount);
    }

    function _decodePayload(
        bytes memory _payload
    ) internal pure returns (string memory tokenAddress_, string memory to_, uint256 amount_) {
        bytes4 selector;
        (selector, tokenAddress_, to_, amount_) = abi.decode(_payload, (bytes4, string, string, uint256));
    }

    /// @dev Modifier to check if the caller is allowed to register token and bridge equivalents.
    function _authorizeRegister(address register) internal virtual;
}
