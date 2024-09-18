---
title: Cross-Chain Messaging Gateway
description: A standard interface for contracts to send and receive cross-chain messages.
author: Francisco Giordano (@frangio), Hadrien Croubois (@Amxx), Ernesto Garcia (@ernestognw), CJ Cobb (@cjcobb23)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
---

## Abstract


## Motivation


## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Message Field Encoding

A cross-chain message consists of a source, destination, payload, and list of attributes.

#### Source & Destination

The source account (sender) and destination account (receiver) MUST be represented using CAIP-10 account identifiers.

This includes a CAIP-2 chain identifier.

Note that these are ASCII-encoded strings.

In some parts of the interface the account and the chain parts of the CAIP-10 identifier will be presented separately rather than as a single string, or the chain part will be implicit.

#### Payload

The payload is an opaque `bytes` value.

#### Attributes

This field encodes a list of key-value pairs.

A gateway MAY support any set of attributes. An empty list MUST always be accepted by a gateway.

Each attribute key MUST have the format of a Solidity function signature, i.e., a name followed by a list of types in parentheses. For example, `minGasLimit(uint256)`.

Each key-value pair MUST be encoded like a Solidity function call, i.e., the first 4 bytes of the hash of the key followed by the ABI-encoded values.

### Source Gateway

An Source Gateway is a contract that offers a protocol to send a message to a destination on another chain. It MUST implement `IGatewaySource`.

```solidity
interface IGatewaySource {
    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id);

    function supportsAttribute(string calldata signature) external view returns (bool);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain identifier [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32}
        string calldata destAccount, // CAIP-10 account address [-.%a-zA-Z0-9]{1,128}
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 messageId);
}
```

#### `supportsAttribute`

Returns a boolean indicating whether the attribute signature is supported by the gateway.

A gateway MAY be upgraded with support for additional attributes. Once present support for an attribute SHOULD NOT be removed to preserve backwards compatibility with users of the gateway.

#### `sendMessage`

Initiates the sending of a message.

Further action MAY be required by the gateway to make the sending of the message effective, such as providing payment for gas. See Post-processing.

MUST generate a unique message identifier and return it. This identifier shall be used to track the lifecycle of the message in events and to perform actions related to the message.

MUST revert if an unsupported attribute key is included. MAY revert if the value of an attribute is not a valid encoding for its expected type.

MAY accept call value (native token) to be sent with the message. MUST revert if call value is included but it is not a feature supported by the gateway. It is unspecified how this value is represented on the destination.

MUST emit a `MessageCreated` event.

MAY emit a `MessageSent` event if it is possible to immediately send the message.

#### Post-processing

After a sender has invoked `sendMessage`, further action MAY be required by the gateway to make the message effective. This is called *post-processing*. For example, some payment is typically required to cover the gas of executing the message at the destination.

The interface for any such action is out of scope of this ERC, but it MUST be able to be performed by a party other than the message sender, and it MUST NOT be able to compromise the eventual receipt of the message.

The gateway MUST emit a `MessageSent` event with the appropriate identifier once post-processing is complete and the message is ready to be delivered on the destination.

### Destination Gateway

An Destination Gateway is a contract that implements a protocol to validate messages sent on other chains and have them received at their destination.

The gateway can operate in Active or Passive Mode.

In both modes, the destination account of a message, aka the receiver, MUST implement a `receiveMessage` function. The use of this function depends on the mode of the gateway as described in the following sections.

```solidity
interface IGatewayReceiver {
    function receiveMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
```

#### Active Mode

The gateway directly invokes `receiveMessage`, and only does so with valid messages. The receiver MUST assume that a message is valid if the caller is a known gateway.

#### Passive Mode

The gateway does not directly invoke `receiveMessage`, but provides a means to validate messages. The receiver allows any party to invoke `receiveMessage`, but if the caller is not a known gateway it MUST validate the message with one before accepting it.

A gateway acting in passive mode MUST implement `IGatewayDestinationPassive`. If a gateway operates exclusively in active mode, the implementation of this interface is OPTIONAL.

```solidity
interface IGatewayDestinationPassive {
    function validateReceivedMessage(
        bytes calldata messageKey,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
```

##### `validateReceivedMessage`

Checks that there is a valid and as yet unexecuted message identified by `messageId`, and that its contents are exactly those passed as arguments along with the caller of the function as the destination account.

MUST revert if the message is invalid or has already been executed.

TBD: Passing full payload or payload hash (as done by Axelar). Same question for attributes, possibly different answer depending on attribute malleability.

#### Dual Mode

A gateway MAY operate in both active and passive modes, or it MAY switch from operating exclusively in active mode to passive mode or vice versa.

A receiver SHOULD support both active and passive modes for any gateway. This is accomplished by first checking whether the caller of `receiveMessage` is a known gateway, and only validating the message on a known gateway if it is not; the first case supports an active mode gateway, while the second case supports a passive mode gateway.

### TBD

- How to "reply" to a message? Duplex gateway? Getter for reverse gateway address? Necessary for some applications, e.g., recovery from token bridging failure?

## Rationale

TBD

## Backwards Compatibility

No backward compatibility issues found.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
