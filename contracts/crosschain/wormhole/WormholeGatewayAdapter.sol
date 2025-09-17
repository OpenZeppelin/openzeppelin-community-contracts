// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {fromUniversalAddress, toUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC7786Attributes} from "../utils/ERC7786Attributes.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {IERC7786Attributes} from "../../interfaces/IERC7786Attributes.sol";

/**
 * @dev An ERC-7786 compliant adapter to send and receive messages via Wormhole.
 *
 * Note: only EVM chains are currently supported
 */
// slither-disable-next-line locked-ether
contract WormholeGatewayAdapter is IERC7786GatewaySource, IWormholeReceiver, Ownable {
    using BitMaps for BitMaps.BitMap;
    using InteroperableAddress for bytes;

    IWormholeRelayer internal immutable _wormholeRelayer;
    uint16 internal immutable _wormholeChainId;
    uint24 private constant EVM_ID_FLAG = 1 << 16;

    // Remote gateway.
    mapping(uint256 chainId => address) private _remoteGateways;

    // Chain equivalence ChainId <> Wormhole
    mapping(uint256 chainId => uint24 wormholeId) private _chainIdToWormhole;
    mapping(uint16 wormholeId => uint256 chainId) private _wormholeToChainId;

    // Message temporary representation, waiting for gas payment in requestRelay
    struct PendingMessage {
        bool pending;
        address sender;
        uint256 value;
        bytes recipient;
        bytes payload;
    }

    uint256 private _lastMsgId;
    mapping(bytes32 sendId => PendingMessage) private _pending;
    mapping(uint256 chainId => BitMaps.BitMap) private _executed;

    /// @dev A message was relayed to Wormhole (part of the post processing of the outbox ids created by {sendMessage})
    event MessageRelayed(bytes32 sendId);

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(uint256 chainId, address remote);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(uint256 chainId, uint16 wormholeId);

    error InvalidAttributeEncoding(bytes attribute);
    error DuplicatedAttribute();
    error UnauthorizedCaller(address);
    error InvalidOriginGateway(uint16 wormholeSourceChain, bytes32 wormholeSourceAddress);
    error ReceiverExecutionFailed();
    error UnsupportedChainId(uint256 chainId);
    error UnsupportedWormholeChain(uint16 wormholeId);
    error ChainEquivalenceAlreadyRegistered(uint256 chainId, uint16 wormhole);
    error RemoteGatewayAlreadyRegistered(uint256 chainId);
    error InvalidSendId(bytes32 sendId);
    error AdditionalMessagesNotSupported();
    error MessageAlreadyExecuted(uint256 chainId, bytes32 outboxId);

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(_wormholeRelayer), UnauthorizedCaller(msg.sender));
        _;
    }

    /// @dev Initializes the contract with the Wormhole gateway and the initial owner.
    constructor(IWormholeRelayer wormholeRelayer, uint16 wormholeChainId, address initialOwner) Ownable(initialOwner) {
        _wormholeRelayer = wormholeRelayer;
        _wormholeChainId = wormholeChainId;
    }

    /// @dev Returns the local Wormhole relayer
    function relayer() public view virtual returns (address) {
        return address(_wormholeRelayer);
    }

    /// @dev Returns whether a binary interoperable chain id is supported.
    function supportedChain(bytes memory chain) public view virtual returns (bool) {
        (bool success, uint256 chainId, ) = chain.tryParseEvmV1();
        return success && supportedChain(chainId);
    }

    /// @dev Returns whether an EVM chain id is supported.
    function supportedChain(uint256 chainId) public view virtual returns (bool) {
        return _chainIdToWormhole[chainId] & EVM_ID_FLAG == EVM_ID_FLAG;
    }

    /// @dev Returns the Wormhole chain id that correspond to a given binary interoperable chain id.
    function getWormholeChain(bytes memory chain) public view virtual returns (uint16) {
        (uint256 chainId, ) = chain.parseEvmV1();
        return getWormholeChain(chainId);
    }

    /// @dev Returns the Wormhole chain id that correspond to a given EVM chain id.
    function getWormholeChain(uint256 chainId) public view virtual returns (uint16) {
        uint24 wormholeId = _chainIdToWormhole[chainId];
        require(wormholeId & EVM_ID_FLAG == EVM_ID_FLAG, UnsupportedChainId(chainId));
        return uint16(wormholeId);
    }

    /// @dev Returns the EVM chain id for a given Wormhole chain id.
    function getChainId(uint16 wormholeId) public view virtual returns (uint256) {
        uint256 chainId = _wormholeToChainId[wormholeId];
        require(chainId != 0, UnsupportedWormholeChain(wormholeId));
        return chainId;
    }

    /// @dev Returns the address of the remote gateway for a given binary interoperable chain id.
    function getRemoteGateway(bytes memory chain) public view virtual returns (address) {
        (uint256 chainId, ) = chain.parseEvmV1();
        return getRemoteGateway(chainId);
    }

    /// @dev Returns the address of the remote gateway for a given EVM chain id.
    function getRemoteGateway(uint256 chainId) public view virtual returns (address) {
        address addr = _remoteGateways[chainId];
        require(addr != address(0), UnsupportedChainId(chainId));
        return addr;
    }

    /// @dev Registers a chain equivalence between a binary interoperable chain id and a Wormhole chain id.
    function registerChainEquivalence(
        bytes calldata chain,
        uint16 wormholeId
    ) public virtual /*onlyOwner in registerChainEquivalence*/ {
        (uint256 chainId, ) = chain.parseEvmV1Calldata();
        registerChainEquivalence(chainId, wormholeId);
    }

    /// @dev Registers a chain equivalence between an EVM chain id and a Wormhole chain id.
    function registerChainEquivalence(uint256 chainId, uint16 wormholeId) public virtual onlyOwner {
        require(
            _chainIdToWormhole[chainId] == 0 && _wormholeToChainId[wormholeId] == 0,
            ChainEquivalenceAlreadyRegistered(chainId, wormholeId)
        );

        _chainIdToWormhole[chainId] = wormholeId | EVM_ID_FLAG;
        _wormholeToChainId[wormholeId] = chainId;
        emit RegisteredChainEquivalence(chainId, wormholeId);
    }

    /// @dev Registers the address of a remote gateway (binary interoperable address version).
    function registerRemoteGateway(bytes calldata remote) public virtual /*onlyOwner in registerRemoteGateway*/ {
        (uint256 chainId, address addr) = remote.parseEvmV1Calldata();
        registerRemoteGateway(chainId, addr);
    }

    /// @dev Registers the address of a remote gateway (EVM version).
    function registerRemoteGateway(uint256 chainId, address addr) public virtual onlyOwner {
        require(supportedChain(chainId), UnsupportedChainId(chainId));
        require(_remoteGateways[chainId] == address(0), RemoteGatewayAlreadyRegistered(chainId));
        _remoteGateways[chainId] = addr;
        emit RegisteredRemoteGateway(chainId, addr);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) public pure returns (bool) {
        return selector == IERC7786Attributes.requestRelay.selector;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 sendId) {
        for (uint256 i = 0; i < attributes.length; ++i) {
            bytes4 selector = attributes[i].length < 0x04 ? bytes4(0) : bytes4(attributes[i]);
            require(supportsAttribute(selector), UnsupportedAttribute(selector));
        }

        // We need a unique message identifier.
        bytes32 msgId = bytes32(++_lastMsgId);

        // Case 1. We don't have a requestRelay attribute.
        // - The message is saved, waiting for a call to requestRelay.
        //
        // Case 2. We have a requestRelay attribute.
        // - The message is sent directly
        //
        // Case 3. We have multiple duplicated instances of the requestRelay attribute.
        // - revert
        if (attributes.length == 0) {
            sendId = msgId;

            // Note: this reverts with UnsupportedChainId if the recipient is not on a supported chain.
            // No real need to check the return value.
            getRemoteGateway(recipient);

            // Store the message for future execution in {requestRelay}
            _pending[sendId] = PendingMessage(true, msg.sender, msg.value, recipient, payload);

            emit MessageSent(
                sendId,
                InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
                recipient,
                payload,
                msg.value,
                attributes
            );
        } else if (attributes.length == 1) {
            sendId = 0;

            // Parse the attribute details
            (bool success, uint256 receiverValue, uint256 gasLimit, address refundRecipient) = ERC7786Attributes
                .tryDecodeRequestRelay(attributes[0]);
            require(success, InvalidAttributeEncoding(attributes[0]));

            // Send the message.
            // msgId is used for uniqueness and replay protection, even if its not an actual sendId (not part of the
            // `MessageSent` event and not used for relaying)
            _sendMessage(msgId, recipient, payload, msg.sender, msg.value, receiverValue, gasLimit, refundRecipient);

            emit MessageSent(
                sendId,
                InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
                recipient,
                payload,
                receiverValue,
                attributes
            );
        } else {
            revert DuplicatedAttribute();
        }
    }

    /// @dev Returns a quote for the value that must be passed to {requestRelay}
    function quoteRelay(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata /*payload*/,
        bytes[] calldata /*attributes*/,
        uint256 value,
        uint256 gasLimit,
        address /*refundRecipient*/
    ) external view returns (uint256) {
        (uint256 cost, ) = _wormholeRelayer.quoteEVMDeliveryPrice(getWormholeChain(recipient), value, gasLimit);
        return cost - value;
    }

    /// @dev Relay a message that was initiated by {sendMessage}.
    function requestRelay(bytes32 sendId, uint256 gasLimit, address refundRecipient) external payable {
        PendingMessage memory pmsg = _pending[sendId];
        require(pmsg.pending, InvalidSendId(sendId));
        delete _pending[sendId];

        _sendMessage(
            sendId,
            pmsg.recipient,
            pmsg.payload,
            pmsg.sender,
            msg.value + pmsg.value,
            pmsg.value,
            gasLimit,
            refundRecipient
        );

        emit MessageRelayed(sendId);
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory adapterPayload,
        bytes[] memory additionalMessages,
        bytes32 wormholeSourceAddress,
        uint16 wormholeSourceChain,
        bytes32 deliveryHash
    ) public payable virtual onlyWormholeRelayer {
        require(additionalMessages.length == 0, AdditionalMessagesNotSupported());

        (bytes32 sendId, bytes memory sender, bytes memory recipient, bytes memory payload) = abi.decode(
            adapterPayload,
            (bytes32, bytes, bytes, bytes)
        );

        // Wormhole to EVM translation
        uint256 chainId = getChainId(wormholeSourceChain);
        address addr = getRemoteGateway(chainId);

        // check message validity
        // - `wormholeSourceAddress` is the remote gateway on the origin chain.
        require(
            addr == fromUniversalAddress(wormholeSourceAddress),
            InvalidOriginGateway(wormholeSourceChain, wormholeSourceAddress)
        );

        // prevent replay - deliveryHash might not be unique if a message is relayed multiple time
        require(!_executed[chainId].get(uint256(sendId)), MessageAlreadyExecuted(chainId, sendId));
        _executed[chainId].set(uint256(sendId));

        (, address target) = recipient.parseEvmV1();
        bytes4 result = IERC7786Receiver(target).receiveMessage{value: msg.value}(deliveryHash, sender, payload);
        require(result == IERC7786Receiver.receiveMessage.selector, ReceiverExecutionFailed());
    }

    function _sendMessage(
        bytes32 id,
        bytes memory recipient,
        bytes memory payload,
        address sender,
        uint256 totalValue,
        uint256 receiverValue,
        uint256 gasLimit,
        address refundRecipient
    ) private {
        uint16 targetChain = getWormholeChain(recipient);
        address targetAddress = getRemoteGateway(recipient);
        _wormholeRelayer.sendPayloadToEvm{value: totalValue}(
            targetChain,
            targetAddress,
            abi.encode(id, InteroperableAddress.formatEvmV1(block.chainid, sender), recipient, payload),
            receiverValue,
            gasLimit,
            targetChain,
            refundRecipient
        );
    }
}
