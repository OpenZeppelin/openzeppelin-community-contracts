// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";

/**
 * @dev N of M gateway: Sends your message through M independent gateways. It will be delivered to the receiver by an
 * equivalent aggregator on the destination chain if N of the M gateways agree.
 */
contract ERC7786Aggregator is IERC7786GatewaySource, IERC7786Receiver, Ownable, Pausable {
    using EnumerableSet for *;
    using Strings for *;

    struct Outbox {
        address gateway;
        bytes32 id;
    }

    struct Tracker {
        mapping(address => bool) receivedBy;
        uint8 countReceived;
        bool executed;
    }

    event OutboxDetails(bytes32 indexed outboxId, Outbox[] outbox);
    event Received(bytes32 indexed receiveId, address gateway);
    event ExecutionSuccess(bytes32 indexed receiveId);
    event ExecutionFailed(bytes32 indexed receiveId);
    event GatewayAdded(address indexed gateway);
    event GatewayRemoved(address indexed gateway);
    event ThresholdUpdated(uint8 threshold);

    error ERC7786AggregatorValueNotSupported();
    error ERC7786AggregatorInvalidCrosschainSender();
    error ERC7786AggregatorAlreadyExecuted();
    error ERC7786AggregatorRemoteNotRegistered(string caip2);
    error ERC7786AggregatorGatewayAlreadyRegistered(address gateway);
    error ERC7786AggregatorGatewayNotRegistered(address gateway);
    error ERC7786AggregatorThresholdViolation();
    error ERC7786AggregatorInvalidExecutionReturnValue();

    /****************************************************************************************************************
     *                                        S T A T E   V A R I A B L E S                                         *
     ****************************************************************************************************************/

    /// @dev address of the matching aggregator for a given CAIP2 chain
    mapping(string caip2 => string) private _remotes;

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
    event RemoteRegistered(string chainId, string aggregator);
    error RemoteAlreadyRegistered(string chainId);

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
        string calldata destinationChain,
        string memory receiver,
        bytes memory payload,
        bytes[] memory attributes
    ) public payable virtual whenNotPaused returns (bytes32 outboxId) {
        if (attributes.length > 0) revert UnsupportedAttribute(bytes4(attributes[0]));
        if (msg.value > 0) revert ERC7786AggregatorValueNotSupported();
        // address of the remote aggregator, revert if not registered
        string memory aggregator = getRemoteAggregator(destinationChain);

        // wrapping the payload
        bytes memory wrappedPayload = abi.encode(++_nonce, msg.sender.toChecksumHexString(), receiver, payload);

        // Post on all gateways
        Outbox[] memory outbox = new Outbox[](_gateways.length());
        bool needsId = false;
        for (uint256 i = 0; i < outbox.length; ++i) {
            address gateway = _gateways.at(i);
            // send message
            bytes32 id = IERC7786GatewaySource(gateway).sendMessage(
                destinationChain,
                aggregator,
                wrappedPayload,
                attributes
            );
            // if ID, track it
            if (id != bytes32(0)) {
                outbox[i] = Outbox(gateway, id);
                needsId = true;
            }
        }

        if (needsId) {
            outboxId = keccak256(abi.encode(outbox));
            emit OutboxDetails(outboxId, outbox);
        }

        emit MessagePosted(
            outboxId,
            CAIP10.local(msg.sender),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );
    }

    // ============================================== IERC7786Receiver ===============================================

    /**
     * @inheritdoc IERC7786Receiver
     *
     * @dev This function serves a dual purpose:
     *
     * It will be called by ERC-7786 gateways with message coming from the the corresponding aggregator on the source
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
     * * the message is not properly formatted or does not originate from the registered aggregator on the source
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
    function executeMessage(
        string calldata /*messageId*/, // gateway specific, empty or unique
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable virtual whenNotPaused returns (bytes4) {
        // Check sender is a trusted remote aggregator
        if (!_remotes[sourceChain].equal(sender)) revert ERC7786AggregatorInvalidCrosschainSender();

        // Message reception tracker
        bytes32 id = keccak256(abi.encode(sourceChain, sender, payload, attributes));
        Tracker storage tracker = _trackers[id];

        // If call is first from a trusted gateway
        if (_gateways.contains(msg.sender) && !tracker.receivedBy[msg.sender]) {
            // Count number of time received
            tracker.receivedBy[msg.sender] = true;
            ++tracker.countReceived;
            emit Received(id, msg.sender);

            // if already executed, leave gracefully
            if (tracker.executed) return IERC7786Receiver.executeMessage.selector;
        } else if (tracker.executed) {
            revert ERC7786AggregatorAlreadyExecuted();
        }

        // Parse payload
        (, string memory originalSender, string memory receiver, bytes memory unwrappedPayload) = abi.decode(
            payload,
            (uint256, string, string, bytes)
        );

        // If ready to execute, and not yet executed
        if (tracker.countReceived >= getThreshold()) {
            // prevent re-entry
            tracker.executed = true;

            bytes memory call = abi.encodeCall(
                IERC7786Receiver.executeMessage,
                (uint256(id).toHexString(32), sourceChain, originalSender, unwrappedPayload, attributes)
            );
            // slither-disable-next-line reentrancy-no-eth
            (bool success, bytes memory returndata) = receiver.parseAddress().call(call);

            if (!success) {
                // rollback to enable retry
                tracker.executed = false;
                emit ExecutionFailed(id);
            } else if (bytes32(returndata) == bytes32(IERC7786Receiver.executeMessage.selector)) {
                // call successful and correct value returned
                emit ExecutionSuccess(id);
            } else {
                // call successful but invalid value returned, we need to revert the subcall
                revert ERC7786AggregatorInvalidExecutionReturnValue();
            }
        }

        return IERC7786Receiver.executeMessage.selector;
    }

    // =================================================== Getters ===================================================

    function getGateways() public view virtual returns (address[] memory) {
        return _gateways.values();
    }

    function getThreshold() public view virtual returns (uint8) {
        return _threshold;
    }

    function getRemoteAggregator(string calldata caip2) public view virtual returns (string memory) {
        string memory aggregator = _remotes[caip2];
        if (bytes(aggregator).length == 0) revert ERC7786AggregatorRemoteNotRegistered(caip2);
        return aggregator;
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

    function registerRemoteAggregator(string memory caip2, string memory aggregator) public virtual onlyOwner {
        _registerRemoteAggregator(caip2, aggregator);
    }

    function pause() public virtual onlyOwner {
        _pause();
    }

    function unpause() public virtual onlyOwner {
        _unpause();
    }

    /// @dev Recovery method in case value is ever received through {executeMessage}
    function sweep(address payable to) public virtual onlyOwner {
        Address.sendValue(to, address(this).balance);
    }

    // ================================================== Internal ===================================================

    function _addGateway(address gateway) internal virtual {
        if (!_gateways.add(gateway)) revert ERC7786AggregatorGatewayAlreadyRegistered(gateway);
        emit GatewayAdded(gateway);
    }

    function _removeGateway(address gateway) internal virtual {
        if (!_gateways.remove(gateway)) revert ERC7786AggregatorGatewayNotRegistered(gateway);
        if (_threshold > _gateways.length()) revert ERC7786AggregatorThresholdViolation();
        emit GatewayRemoved(gateway);
    }

    function _setThreshold(uint8 newThreshold) internal virtual {
        if (newThreshold == 0 || _threshold > _gateways.length()) revert ERC7786AggregatorThresholdViolation();
        _threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function _registerRemoteAggregator(string memory caip2, string memory aggregator) internal virtual {
        _remotes[caip2] = aggregator;

        emit RemoteRegistered(caip2, aggregator);
    }
}
