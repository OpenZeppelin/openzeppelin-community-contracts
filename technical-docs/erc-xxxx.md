---
eip: XXXX
title: Nomenclature and properties of cross-chain message-passing systems.
description: todo
author: Hadrien Croubois (@Amxx), Ernesto García (@ernestognw), Francisco Giordano (@frangio)
discussions-to: toto
status: Draft
type: Standards Track
category: ERC
created: 2024-08-01
---

## Abstract

The following standard focuses on providing an unambiguous name to the different elements involved in cross-chain communication and defining some properties that these elements may or may not have. This is preparation work for a standard cross-chain communication interface.

## Motivation

Crosschain message-passing systems, also known as bridges, allow communication between smart contracts living on different blockchains. There exists a large diversity of such systems, with different degrees of decentralization. These many systems use different components, implement different interfaces, and provide different guarantees to the users. This often makes it difficult to compare them and transfer knowledge and reasoning from one system to another.

The objective of this ERC is to provide a standard nomenclature for describing the actors and components involved in cross-chain communication. It also lists properties that such systems may or may not have.

The list of properties is not a wishlist of features that systems SHOULD implement. In some cases, some properties might not be desirable. Being clear about which properties are present (and how they are achieved) and which are not will help users determine which systems meet their needs.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED",  "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### Definitions

#### Source chain

The blockchain from which the cross-chain message is originating.

#### Requester

The account, on the source chain, that is sending the cross-chain message. In the context of an EVM source chain, this can be an EOA or a smart contract.

#### Destination chain

The blockchain to which the cross-chain message is intended.

#### Target

The account, on the destination chain, that should receive the message. In the context of an EVM source chain, this can be an EOA or a smart contract, though most usecases will target smart contracts.

#### Payload

The data contents (i.e., a byte string) of the message the requester sends to the target.

#### Message

Messages are the objects that are being transmitted between chains. The message is sent by a requester, to a target, and contains a payload. The message may also contain some additional optional parameters and assets attached to it.

We refer to the payload and parameters as the "message contents".

#### Message delivery

The process by which the message becomes available on the destination chain. This process may include message execution.

#### Message execution

I a message's payload is not empty, and if the target of the message is a smart contract, then the message should be processed by the payload. This may be done in different ways. One common mechanism is to perform a call operation on the target, using the payload as calldata. We call that process message execution. As with all call operations, the execution of a message can fail/revert.

#### Forwarder (or Relayer?)

In some cross-chain systems, the transmission of the message may require the help of a forwarder to facilitate the transmission. The forwarder may provide additional parameters, or payment but shall not be able to alter the target and the payload decided by the requester.

#### Gateway

In some cross-chain systems, the creation and delivery of messages may involve entry-point smart contracts on either chain. We call these contracts gateways. Some systems will require gateways on both the source chain and destination chains while other systems will only use one gateway. The presence and nature of the gateway varies radically between existing cross-chain message-passing systems.

### Properties

This section provides a list of properties that can be used to describe a cross-chain message-passing system. Not all systems have all the properties. In some cases, some of these properties may not be achievable or desirable.

#### Identifiability

> A message is uniquely identifiable.

This is a fundamental property that is required for other properties, such as **Non-Replayability** to make sense. All cross-chain systems SHOULD have this property.

#### Validity

> A payload is only executed on the target if the message was submitted by the requester.

This is a basic security property that all cross-chain systems SHOULD have.

#### Non-Replayability

> A message is successfully executed on the target at most one time.

This is a basic security property that all cross-chain systems SHOULD have.

#### Retriability

> A message's execution can be retried multiple times.

When combined with **Non-Replayability**, this property allows the message execution to be retried multiple times in case the execution fails, with the guarantee that the message will not be successfully executed more than once. This process can be used to achieve **Eventual Liveness**.

#### Ordered Execution

> Messages are executed in the same order as they were submitted

Most cross-chain systems do NOT have this property. In general, this property may not be desirable as it could lead to DoS.

A system that doesn't have this property is said to support **Out-of-order Execution**.

#### Duplicability

> A requester is able to send the same payload to the same target multiple times. Each request is seen as a different message.

When combined with **Non-Replayability**, each submission will be executed at most once, meaning that a payload will be executed on the target at most N times, with N the number of times it was submitted by the requester.

**TODO:** find a better name for this property ?

#### Liveness

> A message that was submitted is executed.

A weaker version of this property is **Eventual Liveness**:

> A message that was submitted is eventually executed, potentially after some external intervention.

**Eventual Liveness** can be achieved through **Retriability**.

#### Observability

> An observer is able to track the status of a message.

This property may be available with restrictions on who the observer is. For example, a system may provide observability to off-chain observers through an API/explorer, but at the same time not provide observability to the requester if the status of the message is not tracked on the source chain.

**TODO:** add more details about identifiers.

## Rationale

TODO

## Security Considerations

N/A

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
