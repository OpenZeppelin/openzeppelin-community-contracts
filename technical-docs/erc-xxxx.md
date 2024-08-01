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

todo

#### Requester

todo

#### Destination chain

todo

#### Target

todo

#### Payload

todo

#### Message

todo

#### Forwarder

todo

#### Gateway

todo

### Properties

This section provides a list of properties that can be used to describe a cross-chain message-passing system. Not all systems have all the properties. In some cases, some of these properties may not be achievable or desirable.

#### Validity

A payload SHOULD only be executed on the target if the message was submitted by the requester.

**Note:** This is a basic security property that all cross-chain systems SHOULD have.

#### Non-Replayability

A message SHOULD be successfully executed on the target at most one time.

**Note:** This is a basic security property that all cross-chain systems SHOULD have.

#### Retriability

A message's execution CAN be retried multiple times.

**Note:** When combined with **Non-Replayability**, this property allows the message execution to be retried multiple times in case the execution fails, with the guarantee that the message will not be successfully executed more than once. This process can be used to achieve **Eventual Liveness**.

#### Ordered Execution

Messages SHOULD be executed in the same order as they were submitted

**Note:** Most cross-chain systems do NOT have this property. In general, this property may not be desirable as it could lead to DoS.

**Note:** A system that doesn't have this property is said to support **Out-of-order Execution**.

#### Duplicability

A requester SHOULD be able to send the same payload to the same target multiple times. Each request should be seen as a different message.

**Note:** When combined with **Non-Replayability**, each submission will be executed at most once, meaning that a payload will be executed on the target at most N times, with N the number of times it was submitted by the requester.

#### Liveness

A message that was submitted MUST be executed.

A weaker version of this property is **Eventual Liveness**: A message that was submitted SHOULD eventually be executed, potentially after some external intervention.

**Note:** **Eventual Liveness** can be achieved through **Retriability**.

#### Observability

An observer SHOULD be able to track the status of a message.

**Note:** This property may be available with restrictions on who the observer is. For example, a system may provide observability to off-chain observers through an API/explorer, but at the same time not provide observability to the requester if the status of the message is not tracked on the source chain.

## Rationale

TODO

## Security Considerations

N/A

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
