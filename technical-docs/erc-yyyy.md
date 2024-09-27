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

Crosschain message-passing systems (or bridges) allow communication between smart contracts deployed on different blockchains. There is a large diversity of such systems with multiple degrees of decentralization, with various components, that implement different interfaces, and provide different guarantees to the users.

Because almost every protocol implementing a different workflow, using a specific interface, portability between bridges is basically impossible. This also forbid the development of generic contracts that rely on cross chain communication.

The objective of the ERC is to provide a standard interface, and a corresponding workflow, for performing cross-chain communication between contracts. Existing cross-chain communication protocols, that do not nativelly implement this interface, should be able to adopt it using adapter gateway contracts.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Message Field Encoding

A cross-chain message consists of a sender, receiver, payload, and list of attributes.

#### Sender & Receiver

The sender account (in the source chain) and receiver account (in the destination chain) MUST be represented using CAIP-10 account identifiers. Note that these are ASCII-encoded strings.

A CAIP-10 account identifier embeds a CAIP-2 chain identifier along with an address. In some parts of the interface, the address and the chain parts will be provided separately rather than as a single string, or the chain part will be implicit.

#### Payload

The payload is an opaque `bytes` value.

#### Attributes

Attributes are structured pieces of message data and/or metadata. Each attribute is a key-value pair, where the key determines the type and encoding of the value, as well as its meaning and behavior.

Some attributes are message data that must be sent to the receiver, although they can be transformed as long as their meaning is preserved. Other attributes are metadata that will be used by the intervening gateways and potentially removed before the message reaches the receiver.

The set of attributes is extensible. It is RECOMMENDED to publish standardize attributes and their characteristics by publishing them as ERCs. A gateway MAY support any set of attributes. An empty attribute list MUST always be accepted by a gateway.

Each attribute key MUST have the format of a Solidity function signature, i.e., a name followed by a list of types in parentheses. For example, `minGasLimit(uint256)`.

In this specification attributes are encoded as an array of `bytes` (i.e., `bytes[]`). Each element of the array MUST encode an attribute in the form of a Solidity function call, i.e., the first 4 bytes of the hash of the key followed by the ABI-encoded value.

##### Standard Attributes

The following standard attributes MAY be supported by a gateway.

- `postProcessingOwner(address)`: The address of the account that shall be in charge of message post-processing.

### Source Gateway

An Source Gateway is a contract that offers a protocol to send a message to a receiver on another chain. It MUST implement `IGatewaySource`.

```solidity
interface IGatewaySource {
    event MessageCreated(bytes32 outboxId, string sender, string receiver, bytes payload, uint256 value, bytes[] attributes);
    event MessageSent(bytes32 indexed outboxId);

    function supportsAttribute(bytes4 signature) external view returns (bool);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}
```

#### `supportsAttribute`

Returns a boolean indicating whether an attribute is supported by the gateway, identified by the selector computed from the attribute signature.

A gateway MAY be upgraded with support for additional attributes. Once present support for an attribute SHOULD NOT be removed to preserve backwards compatibility with users of the gateway.

#### `sendMessage`

Initiates the sending of a message.

Further action MAY be required by the gateway to make the sending of the message effective, such as providing payment for gas. See Post-processing.

MUST revert if an unsupported attribute key is included. MAY revert if the value of an attribute is not a valid encoding for its expected type.

MAY accept call value (native token) to be sent with the message. MUST revert if call value is included but it is not a feature supported by the gateway. It is unspecified how this value is represented on the destination.

MAY generate and return a unique non-zero *outbox identifier*, otherwise returning zero. This identifier shall be used to track the lifecycle of the message in the outbox in events and for post-processing.

MUST emit a `MessageCreated` event.

MAY emit a `MessageSent` event if it is possible to immediately send the message.

#### Post-processing

After a sender has invoked `sendMessage`, further action MAY be required by the gateway to make the message effective. This is called *post-processing*. For example, some payment is typically required to cover the gas of executing the message at the destination.

The exact interface for any such action is out of scope of this ERC. If the `postProcessingOwner` attribute is supported and present, such actions MUST be restricted to the specified account, otherwise they MUST be able to be performed by any party in a way that MUST NOT be able to compromise the eventual receipt of the message.

The gateway MUST emit a `MessageSent` event with the appropriate identifier once post-processing is complete and the message is ready to be delivered on the destination.

### Destination Gateway

A Destination Gateway is a contract that implements a protocol to validate messages sent on other chains and have them received at their destination.

The gateway can operate in Active or Passive Mode.

In both modes, the destination account of a message, aka the receiver, MUST implement a `receiveMessage` function. The use of this function depends on the mode of the gateway as described in the following sections.

```solidity
interface IGatewayReceiver {
    function receiveMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata sourceChain,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
```

#### Active Mode

The gateway directly invokes `receiveMessage`, and only does so with valid messages. The receiver MUST assume that a message is valid if the caller is a known gateway.

The arguments `gateway` and `gatewayMessageKey` are unused in active mode and SHOULD be zero and empty respectively.

#### Passive Mode

The gateway does not directly invoke `receiveMessage`, but provides a means to validate messages. The receiver allows any party to invoke `receiveMessage`, but if the caller is not a known gateway it MUST check that the gateway provided as an argument is a known gateway, and it MUST validate the message against it before accepting it, forwarding the message key.

A gateway acting in passive mode MUST implement `IGatewayDestinationPassive`. If a gateway operates exclusively in active mode, the implementation of this interface is OPTIONAL.

```solidity
interface IGatewayDestinationPassive {
    function validateReceivedMessage(
        bytes calldata messageKey,
        string calldata sourceChain,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
```

##### `validateReceivedMessage`

Checks that there is a valid and as yet unexecuted message whose contents are exactly those passed as arguments and whose receiver is the caller of the function. The message key MAY be an identifier, or another piece of data necessary for validation.

MUST revert if the message is invalid or has already been executed.

TBD: Passing full payload or payload hash (as done by Axelar). Same question for attributes, possibly different answer depending on attribute malleability.

#### Dual Active-Passive Mode

A gateway MAY operate in both active and passive modes, or it MAY switch from operating exclusively in active mode to passive mode or vice versa.

A receiver SHOULD support both active and passive modes for any gateway. This is accomplished by first checking whether the caller of `receiveMessage` is a known gateway, and only validating the message if it is not; the first case supports an active mode gateway, while the second case supports a passive mode gateway.

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
