---
title: Cross-Chain Messaging Gateway
description: A standard interface for contracts to send and receive cross-chain messages.
author: <a comma separated list of the author's or authors' name + GitHub username (in parenthesis), or name and email (in angle brackets).  Example, FirstName LastName (@GitHubUsername), FirstName LastName <foo@bar.com>, FirstName (@GitHubUsername) and GitHubUsername (@GitHubUsername)>
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
requires: <EIP number(s)> # Only required when you reference an EIP in the `Specification` section. Otherwise, remove this field.
---

## Abstract


## Motivation


## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Message

```solidity
struct Message {
    string source; // CAIP-10 identifier
    string destination;  // CAIP-10 identifier
    bytes payload;
    bytes[] attributes;
}
```

#### `attributes`

This field encodes a list of key-value pairs. A gateway may support any subset of standard or proprietary attributes. An empty list must always be accepted by a gateway.

##### Encoding

TBD

##### Standard attributes

TBC

| Key | Value |
|-----|-------|
| `token/native` | `uint256` |
| `token/erc20` | `(address,uint256)` |
| `token/erc721` | `(address,uint256)` |
| `token/erc1155` | `(address,uint256,uint256)` |
| `minGasLimit` | `uint256` |

### Outgoing Gateway

An Outgoing Gateway is a contract that offers a protocol to send a message to a destination on another chain. It MUST implement `IGatewayOutgoing`.

```solidity
interface IGatewayOutgoing {
    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain identifier [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32}
        string calldata destAccount, // CAIP-10 account address [-.%a-zA-Z0-9]{1,128}
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 messageId);
}
```

#### `sendMessage`

Initiates the sending of a message.

MUST generate a unique message identifier and return it. This identifier shall be used to track the lifecycle of the message in events and to perform actions related to the message.

MUST emit a `MessageCreated` event.

MAY emit a `MessageSent` event if it is possible to immediately send the message.

TBD: Interaction between `payable` and `token/native` attribute.

#### `MessageSent`

It MAY not be possible for `sendMessage` to immediately send a message if additional action (such as payment) is required.

The interface for any such additional action is out of scope of this ERC, but it MUST be able to be performed by a party other than the message sender.

The gateway MUST emit a `MessageSent` event with the appropriate identifier once required actions are completed and the message is ready to be delivered on the destination.

### Incoming Gateway

An Incoming Gateway is a contract that implements a protocol to validate messages sent on other chains.

```solidity
interface IGatewayIncoming {
    event MessageExecuted(bytes32 indexed id);
}
```

This gateway can operate in Active or Passive Mode. In both cases the destination account of a message, aka the receiver, must implement a `receiveMessage` function.

```solidity
interface IGatewayReceiver {
    function receiveMessage(
        bytes32 messageId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
```

#### Active Mode

The gateway will directly invoke `receiveMessage`, and it will only do so with valid messages. The receiver must check that the caller is a known gateway to ensure the validity of the message.

The event `MessageExecuted` must be emitted by the gateway before executing the message on the receiver.

#### Passive Mode

The gateway will not directly invoke `receiveMessage`, but provides a function `validateReceivedMessage` that checks if the message is valid and has never been executed, and otherwise reverts. Any party can invoke `receiveMessage`, and the receiver must use this function on a known gateway before accepting it as valid.

The event `MessageExecuted` must be emitted if a message is valid and as yet unexecuted. If the message has already been validated and/or began to be executed the function must revert.

This interface is OPTIONAL, given that a gateway may operate exclusively in active mode.

```solidity
interface IGatewayIncomingPassive {
    function validateReceivedMessage(
        bytes32 messageId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
```

#### Dual Mode

A receiver SHOULD support both active and passive modes by first checking whether the caller of `receiveMessage` is a known gateway, and if so assuming it is one operating in active mode and thus that the message is valid; otherwise, the receiver must validate the message against a known gateway.

### TBD

- Attribute support detection.
- How to "reply" to a message? Duplex gateway? Getter for reverse gateway address? Necessary for some applications, e.g., recovery from token bridging failure?

## Rationale

TBD

## Backwards Compatibility

No backward compatibility issues found.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
