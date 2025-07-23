// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

/**
 * @dev N of M gateway: Sends your message through M independent gateways. It will be delivered to the receiver by an
 * equivalent bridge on the destination chain if N of the M gateways agree.
 */
contract ERC7786OpenBridge is IERC7786GatewaySource, IERC7786Receiver, Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using InteroperableAddress for bytes;

    struct Outbox {
        address gateway;
        bytes32 id;
    }

    struct Tracker {
        mapping(address => bool) receivedBy;
        uint8 countReceived;
        bool executed;
    }

    event OutboxDetails(bytes32 indexed sendId, Outbox[] outbox);
    event Received(bytes32 indexed receiveId, address gateway);
    event ExecutionSuccess(bytes32 indexed receiveId);
    event ExecutionFailed(bytes32 indexed receiveId);
    event GatewayAdded(address indexed gateway);
    event GatewayRemoved(address indexed gateway);
    event ThresholdUpdated(uint8 threshold);

    error UnsupportedNativeTransfer();
    error ERC7786OpenBridgeInvalidCrosschainSender();
    error ERC7786OpenBridgeAlreadyExecuted();
    error ERC7786OpenBridgeRemoteNotRegistered(bytes2 chainType, bytes chainReference);
    error ERC7786OpenBridgeGatewayAlreadyRegistered(address gateway);
    error ERC7786OpenBridgeGatewayNotRegistered(address gateway);
    error ERC7786OpenBridgeThresholdViolation();
    error ERC7786OpenBridgeInvalidExecutionReturnValue();

    /****************************************************************************************************************
     *                                        S T A T E   V A R I A B L E S                                         *
     ****************************************************************************************************************/

    /// @dev address of the matching bridge for a given CAIP2 chain
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) private _remotes;

    /// @dev Tracking of the received message pending final delivery
    mapping(bytes32 id => Tracker) private _trackers;

    /// @dev List of authorized IERC7786 gateways (M is the length of this set)
    EnumerableSet.AddressSet private _gateways;

    /// @dev Threshold for message reception
    uint8 private _threshold;

    /// @dev Nonce for message deduplication (internal)
    uint256 private _nonce;

    /****************************************************************************************************************
     *                                        E V E N T S   &   E R R O R S                                         *
     ****************************************************************************************************************/
    event RemoteRegistered(bytes remote);
    error RemoteAlreadyRegistered(bytes remote);

    /****************************************************************************************************************
     *                                              F U N C T I O N S                                               *
     ****************************************************************************************************************/
    constructor(address owner_, address[] memory gateways_, uint8 threshold_) Ownable(owner_) {
        for (uint256 i = 0; i < gateways_.length; ++i) {
            _addGateway(gateways_[i]);
        }
        _setThreshold(threshold_);
    }

    // ============================================ IERC7786GatewaySource ============================================

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public view virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    /// @dev Using memory instead of calldata avoids stack too deep errors
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable virtual whenNotPaused returns (bytes32 sendId) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // address of the remote bridge, revert if not registered
        bytes memory bridge = getRemoteBridge(recipient);
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);

        // wrapping the payload
        bytes memory wrappedPayload = abi.encode(++_nonce, sender, recipient, payload);

        // Post on all gateways
        Outbox[] memory outbox = new Outbox[](_gateways.length());
        bool needsId = false;
        for (uint256 i = 0; i < outbox.length; ++i) {
            address gateway = _gateways.at(i);
            // send message
            bytes32 id = IERC7786GatewaySource(gateway).sendMessage(bridge, wrappedPayload, attributes);
            // if ID, track it
            if (id != bytes32(0)) {
                outbox[i] = Outbox(gateway, id);
                needsId = true;
            }
        }

        if (needsId) {
            sendId = keccak256(abi.encode(outbox));
            emit OutboxDetails(sendId, outbox);
        }

        emit MessageSent(sendId, sender, recipient, payload, 0, attributes);
    }

    // ============================================== IERC7786Receiver ===============================================

    /**
     * @inheritdoc IERC7786Receiver
     *
     * @dev This function serves a dual purpose:
     *
     * It will be called by ERC-7786 gateways with message coming from the the corresponding bridge on the source
     * chain. These "signals" are tracked until the threshold is reached. At that point the message is sent to the
     * destination.
     *
     * It can also be called by anyone (including an ERC-7786 gateway) to retry the execution. This can be useful if
     * the automatic execution (that is triggered when the threshold is reached) fails, and someone wants to retry it.
     *
     * When a message is forwarded by a known gateway, a {Received} event is emitted. If a known gateway calls this
     * function more than once (for a given message), only the first call is counts toward the threshold and emits an
     * {Received} event.
     *
     * This function revert if:
     *
     * * the message is not properly formatted or does not originate from the registered bridge on the source
     *   chain.
     * * someone tries re-execute a message that was already successfully delivered. This includes gateways that call
     *   this function a second time with a message that was already executed.
     * * the execution of the message (on the {IERC7786Receiver} receiver) is successful but fails to return the
     *   executed value.
     *
     * This function does not revert if:
     *
     * * A known gateway delivers a message for the first time, and that message was already executed. In that case
     *   the message is NOT re-executed, and the correct "magic value" is returned.
     * * The execution of the message (on the {IERC7786Receiver} receiver) reverts. In that case a {ExecutionFailed}
     *   event is emitted.
     *
     * This function emits:
     *
     * * {Received} when a known ERC-7786 gateway delivers a message for the first time.
     * * {ExecutionSuccess} when a message is successfully delivered to the receiver.
     * * {ExecutionFailed} when a message delivery to the receiver reverted (for example because of OOG error).
     *
     * NOTE: interface requires this function to be payable. Even if we don't expect any value, a gateway may pass
     * some value for unknown reason. In that case we want to register this gateway having delivered the message and
     * not revert. Any value accrued that way can be recovered by the admin using the {sweep} function.
     */
    // slither-disable-next-line reentrancy-no-eth
    function receiveMessage(
        bytes32 /*receiveId*/,
        bytes calldata sender, // Binary Interoperable Address
        bytes calldata payload
    ) public payable virtual whenNotPaused returns (bytes4) {
        // Check sender is a trusted bridge
        require(keccak256(getRemoteBridge(sender)) == keccak256(sender), ERC7786OpenBridgeInvalidCrosschainSender());

        // Message reception tracker
        bytes32 id = keccak256(abi.encode(sender, payload));
        Tracker storage tracker = _trackers[id];

        // If call is first from a trusted gateway
        if (_gateways.contains(msg.sender) && !tracker.receivedBy[msg.sender]) {
            // Count number of time received
            tracker.receivedBy[msg.sender] = true;
            ++tracker.countReceived;
            emit Received(id, msg.sender);

            // if already executed, leave gracefully
            if (tracker.executed) return IERC7786Receiver.receiveMessage.selector;
        } else if (tracker.executed) {
            revert ERC7786OpenBridgeAlreadyExecuted();
        }

        // Parse payload
        (, bytes memory originalSender, bytes memory recipient, bytes memory unwrappedPayload) = abi.decode(
            payload,
            (uint256, bytes, bytes, bytes)
        );

        // If ready to execute, and not yet executed
        if (tracker.countReceived >= getThreshold()) {
            // prevent re-entry
            tracker.executed = true;

            bytes memory call = abi.encodeCall(IERC7786Receiver.receiveMessage, (id, originalSender, unwrappedPayload));
            // slither-disable-next-line reentrancy-no-eth
            (, address target) = recipient.parseEvmV1();
            (bool success, bytes memory returndata) = target.call(call);

            if (!success) {
                // rollback to enable retry
                tracker.executed = false;
                emit ExecutionFailed(id);
            } else if (bytes32(returndata) == bytes32(IERC7786Receiver.receiveMessage.selector)) {
                // call successful and correct value returned
                emit ExecutionSuccess(id);
            } else {
                // call successful but invalid value returned, we need to revert the subcall
                revert ERC7786OpenBridgeInvalidExecutionReturnValue();
            }
        }

        return IERC7786Receiver.receiveMessage.selector;
    }

    // =================================================== Getters ===================================================

    function getGateways() public view virtual returns (address[] memory) {
        return _gateways.values();
    }

    function getThreshold() public view virtual returns (uint8) {
        return _threshold;
    }

    function getRemoteBridge(bytes memory chain) public view virtual returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        return getRemoteBridge(chainType, chainReference);
    }

    function getRemoteBridge(bytes2 chainType, bytes memory chainReference) public view virtual returns (bytes memory) {
        bytes memory addr = _remotes[chainType][chainReference];
        require(bytes(addr).length != 0, ERC7786OpenBridgeRemoteNotRegistered(chainType, chainReference));
        return InteroperableAddress.formatV1(chainType, chainReference, addr);
    }

    // =================================================== Setters ===================================================

    function addGateway(address gateway) public virtual onlyOwner {
        _addGateway(gateway);
    }

    function removeGateway(address gateway) public virtual onlyOwner {
        _removeGateway(gateway);
    }

    function setThreshold(uint8 newThreshold) public virtual onlyOwner {
        _setThreshold(newThreshold);
    }

    function registerRemoteBridge(bytes calldata bridge) public virtual onlyOwner {
        _registerRemoteBridge(bridge);
    }

    function pause() public virtual onlyOwner {
        _pause();
    }

    function unpause() public virtual onlyOwner {
        _unpause();
    }

    /// @dev Recovery method in case value is ever received through {receiveMessage}
    function sweep(address payable to) public virtual onlyOwner {
        Address.sendValue(to, address(this).balance);
    }

    // ================================================== Internal ===================================================

    function _addGateway(address gateway) internal virtual {
        require(_gateways.add(gateway), ERC7786OpenBridgeGatewayAlreadyRegistered(gateway));
        emit GatewayAdded(gateway);
    }

    function _removeGateway(address gateway) internal virtual {
        require(_gateways.remove(gateway), ERC7786OpenBridgeGatewayNotRegistered(gateway));
        require(_threshold <= _gateways.length(), ERC7786OpenBridgeThresholdViolation());
        emit GatewayRemoved(gateway);
    }

    function _setThreshold(uint8 newThreshold) internal virtual {
        require(newThreshold > 0 && newThreshold <= _gateways.length(), ERC7786OpenBridgeThresholdViolation());
        _threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function _registerRemoteBridge(bytes calldata bridge) internal virtual {
        (bytes2 chainType, bytes calldata chainReference, bytes calldata addr) = bridge.parseV1Calldata();
        _remotes[chainType][chainReference] = addr;
        emit RemoteRegistered(bridge);
    }
}
