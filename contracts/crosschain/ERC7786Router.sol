// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";

/**
 * @dev N of M gateway: Sends your message through M independent gateways. It will be delivered to the receiver by an
 * equivalent router on the destination chain if N of the M gateways agree.
 *
 * NOTE: This contract assumes that both sides of the communication are EVM chains
 */
contract ERC7786Router is Ownable, IERC7786GatewaySource, IERC7786Receiver {
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
    /**
     * @dev EVM address of the matching router for a given CAIP2 chain
     *
     * NOTE: storing the address and casting them on the flight is less expensive then loading a precomputed string
     * that takes 3 slots (length + 42 chars)
     */
    mapping(string caip2 => address remote) private _remotes;

    /**
     * @dev Tracking of the received message pending final delivery
     */
    mapping(bytes32 id => Tracker) private _trackers;

    /**
     * @dev List of authorized IERC7786 gateways (M is the length of this set)
     */
    EnumerableSet.AddressSet private _gateways;

    /**
     * @dev Threshold for message reception (the threshold opf the sending side is applied on the receiving side)
     */
    uint8 private _threshold;

    /**
     * @dev Nonce for message deduplication (internal)
     */
    uint256 private _nonce;

    /****************************************************************************************************************
     *                                        E V E N T S   &   E R R O R S                                         *
     ****************************************************************************************************************/
    event RemoteRegistered(uint256 chainId, address remote);
    error RemoteAlreadyRegistered(uint256 chainId);

    /****************************************************************************************************************
     *                                              F U N C T I O N S                                               *
     ****************************************************************************************************************/
    constructor(address owner_, address[] memory gateways_, uint8 threshold_) Ownable(owner_) {
        for (uint256 i = 0; i < gateways_.length; ++i) {
            _addGateway(gateways_[i]);
        }
        _setThreshold(threshold_);
    }

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
    ) external payable returns (bytes32 outboxId) {
        // address of the remote router, revert if not registered
        string memory router = getRemoteRouter(destinationChain);
        string memory sender = CAIP10.local(msg.sender);

        // wrapping the payload
        bytes memory wrappedPayload = abi.encode(++_nonce, getThreshold(), sender, receiver, payload);

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

    /// @inheritdoc IERC7786Receiver
    function executeMessage(
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes4) {
        // Check sender is a trusted remote router
        require(
            _remotes[sourceChain] == sender.parseAddress(),
            "ERC7786Router message must originated from a registered remote router"
        );

        // Message reception tracker
        Tracker storage tracker = _trackers[keccak256(abi.encode(sourceChain, sender, payload, attributes))];

        // Count number of time received
        if (_gateways.contains(msg.sender) && !tracker.receivedBy[msg.sender]) {
            tracker.receivedBy[msg.sender] = true;
            ++tracker.countReceived;
            // TODO emit event (got message)
        }

        // Parse payload
        (, uint8 threshold, string memory originalSender, string memory receiver, bytes memory unwrappedPayload) = abi
            .decode(payload, (uint256, uint8, string, string, bytes));

        // If ready to execute, and not yet executed
        if (tracker.countReceived >= threshold && !tracker.executed) {
            try
                IERC7786Receiver(receiver.parseAddress()).executeMessage(
                    sourceChain,
                    originalSender,
                    unwrappedPayload,
                    attributes
                )
            returns (bytes4 magic) {
                if (magic == IERC7786Receiver.executeMessage.selector) {
                    tracker.executed = true;
                    // TODO emit event (success)
                } else {
                    // TODO emit event (failure)
                }
            } catch {
                // TODO emit event (failure)
            }
        }

        return IERC7786Receiver.executeMessage.selector;
    }

    // TODO: expose that publicly ?
    function _addGateway(address gateway) internal virtual {
        require(!_gateways.add(gateway), "ERC7786Router gateway already present");
        // TODO: add event
    }

    // TODO: expose that publicly ?
    function _removeGateway(address gateway) internal virtual {
        require(!_gateways.remove(gateway), "ERC7786Router gateway not present");
        require(_gateways.length() >= _threshold, "ERC7786 threshold exceeds the number of gateways");
        // TODO: add event
    }

    // TODO: expose that publicly ?
    function _setThreshold(uint8 newThreshold) internal virtual {
        require(newThreshold <= _gateways.length(), "ERC7786 threshold exceeds the number of gateways");
        _threshold = newThreshold;
        // TODO: add event
    }

    function getThreshold() public view virtual returns (uint8) {
        return _threshold;
    }

    function getRemoteRouter(string calldata caip2) public view virtual returns (string memory) {
        address router = _remotes[caip2];
        require(router != address(0), "No remote router known for this destination chain");
        return router.toChecksumHexString();
    }

    function registerRemoteRouter(uint256 chainId, address remote) public virtual onlyOwner {
        string memory caip2 = CAIP2.format("eip155", chainId.toString());

        require(_remotes[caip2] == address(0), RemoteAlreadyRegistered(chainId));
        _remotes[caip2] = remote;

        emit RemoteRegistered(chainId, remote);
    }
}
