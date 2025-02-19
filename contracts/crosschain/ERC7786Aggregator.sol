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
 * equivalent router on the destination chain if N of the M gateways agree.
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

    /****************************************************************************************************************
     *                                        S T A T E   V A R I A B L E S                                         *
     ****************************************************************************************************************/

    /// @dev address of the matching router for a given CAIP2 chain
    mapping(string caip2 => string) private _remoteRouters;

    /// @dev Tracking of the received message pending final delivery
    mapping(bytes32 id => Tracker) private _trackers;

    /// @dev List of authorized IERC7786 gateways (M is the length of this set)
    EnumerableSet.AddressSet private _gateways;

    /// @dev Threshold for message reception (the threshold opf the sending side is applied on the receiving side)
    uint8 private _threshold;

    /// @dev Nonce for message deduplication (internal)
    uint256 private _nonce;

    /****************************************************************************************************************
     *                                        E V E N T S   &   E R R O R S                                         *
     ****************************************************************************************************************/
    event RemoteRegistered(string chainId, string router);
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
    function supportsAttribute(bytes4 selector) external view returns (bool) {
        for (uint256 i = 0; i < _gateways.length(); ++i)
            if (!IERC7786GatewaySource(_gateways.at(i)).supportsAttribute(selector)) return false;
        return true;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        string calldata destinationChain,
        string memory receiver, // using memory instead of calldata avoids stack too deep error
        bytes memory payload, // using memory instead of calldata avoids stack too deep error
        bytes[] memory attributes // using memory instead of calldata avoids stack too deep error
    ) external payable whenNotPaused returns (bytes32 outboxId) {
        require(msg.value == 0, "ERC7786Router: value not supported");
        // address of the remote router, revert if not registered
        string memory router = getRemoteRouter(destinationChain);
        string memory sender = CAIP10.local(msg.sender);

        // wrapping the payload
        bytes memory wrappedPayload = abi.encode(++_nonce, sender, receiver, payload);

        // Post on all gateways
        Outbox[] memory outbox = new Outbox[](_gateways.length());
        bool needsId = false;
        for (uint256 i = 0; i < outbox.length; ++i) {
            address gateway = _gateways.at(i);
            // send message
            bytes32 id = IERC7786GatewaySource(gateway).sendMessage(
                destinationChain,
                router,
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
            // TODO store outbox ? emit event ?
        }

        emit MessagePosted(outboxId, sender, CAIP10.format(destinationChain, receiver), payload, attributes);
    }

    // ============================================== IERC7786Receiver ===============================================

    /// @inheritdoc IERC7786Receiver
    function executeMessage(
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable whenNotPaused returns (bytes4) {
        // Check sender is a trusted remote router
        require(
            _remoteRouters[sourceChain].equal(sender),
            "ERC7786Router message must originated from a registered remote router"
        );

        // Message reception tracker
        Tracker storage tracker = _trackers[keccak256(abi.encode(sourceChain, sender, payload, attributes))];

        // revert early is execution is already in progress (of done)
        require(!tracker.executed, "ERC7786Router message already executed");

        // Count number of time received
        if (_gateways.contains(msg.sender) && !tracker.receivedBy[msg.sender]) {
            tracker.receivedBy[msg.sender] = true;
            ++tracker.countReceived;
            // TODO emit event (got message)
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
            // slither-disable-next-line reentrancy-no-eth
            try
                IERC7786Receiver(receiver.parseAddress()).executeMessage(
                    sourceChain,
                    originalSender,
                    unwrappedPayload,
                    attributes
                )
            returns (bytes4 magic) {
                if (magic == IERC7786Receiver.executeMessage.selector) {
                    // TODO emit event (success)
                } else {
                    // roolback to enable retry
                    tracker.executed = false;
                    // TODO emit event (failure)
                }
            } catch {
                // rollback to enable retry
                tracker.executed = false;
                // TODO emit event (failure)
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

    function getRemoteRouter(string calldata caip2) public view virtual returns (string memory) {
        string memory router = _remoteRouters[caip2];
        require(bytes(router).length == 0, "No remote router known for this destination chain");
        return router;
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

    function registerRemoteRouter(uint256 chainId, address router) public virtual onlyOwner {
        _registerRemoteRouter(CAIP2.format("eip155", chainId.toString()), router.toChecksumHexString());
    }

    function registerRemoteRouter(string memory caip2, string memory router) public virtual onlyOwner {
        _registerRemoteRouter(caip2, router);
    }

    function pause() public virtual onlyOwner {
        _pause();
    }

    function unpause() public virtual onlyOwner {
        _unpause();
    }

    /// @dev Recovery method in case ether is ever received through {executeMessage}
    function drainEth(address payable to) public virtual onlyOwner {
        Address.sendValue(to, address(this).balance);
    }

    // ================================================== Internal ===================================================

    function _addGateway(address gateway) internal virtual {
        require(!_gateways.add(gateway), "ERC7786Router gateway already present");
        // TODO: add event
    }

    function _removeGateway(address gateway) internal virtual {
        require(!_gateways.remove(gateway), "ERC7786Router gateway not present");
        require(_threshold <= _gateways.length(), "ERC7786 threshold exceeds the number of gateways");
        // TODO: add event
    }

    function _setThreshold(uint8 newThreshold) internal virtual {
        require(newThreshold > 0, "ERC7786 threshold cannot be 0");
        require(newThreshold <= _gateways.length(), "ERC7786 threshold exceeds the number of gateways");
        _threshold = newThreshold;
        // TODO: add event
    }

    // NOTE: once a router is registered for a given chainId, it cannot be updated
    function _registerRemoteRouter(string memory caip2, string memory router) internal virtual {
        require(bytes(_remoteRouters[caip2]).length == 0, RemoteAlreadyRegistered(caip2));
        _remoteRouters[caip2] = router;

        emit RemoteRegistered(caip2, router);
    }
}
